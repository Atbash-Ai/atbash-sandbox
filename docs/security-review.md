# Security review and remediation tracker

Reviewed against commit `2d5112806ab5505596ee98ed038ae859e0b166f2` and the
local remediation worktree. This document separates repository fixes from
controls that require organization, service, or cloud-provider changes.

## Repository findings

| Finding | Original severity | Local status | Evidence / remediation |
|---|---:|---|---|
| Prehook allowed commands when judge failed | High | Fixed | `prehook/atbash-prehook.sh` now requires a valid `ALLOW`, has a bounded timeout, validates dependencies and JSON, and tests outage/error paths. |
| CLI and base image used mutable `latest` references | High | Fixed for repository defaults | CLI is `0.5.8`; Docker base is pinned to an immutable manifest digest; Cloud Build uses a commit-derived tag. Automated digest/version updates still require review. |
| Agent key inherited by arbitrary child processes | High | Mitigated for Docker entrypoint | `entrypoint.sh` validates and atomically persists an injected key to a mode-0600 config, then unsets it before `exec`. Codespaces no longer copies the local key into both environment scopes. Replit does not use this entrypoint and remains a weaker target. |
| Runtime egress is unrestricted | High | Open — deployment control | Apply DNS/firewall/VPC egress allowlists and block cloud metadata endpoints. The repository cannot impose one portable rule across all advertised providers. |
| No automated security CI | Medium | Fixed locally | `.github/workflows/security.yml` adds syntax, ShellCheck, unit, Compose, Gitleaks, image build, non-root assertion, and Trivy checks. |
| No dependency update automation | Medium | Fixed locally | `.github/dependabot.yml`. |
| No branch protection/rulesets | Medium | Open — GitHub admin control | Require PRs, independent review, required security checks, stale-approval dismissal, and block force-push/deletion on `main`. |
| Bash DEBUG trap is bypassable by shell owner | Medium | Documented, architectural | Keep it advisory. Production enforcement belongs in an out-of-process execution broker/tool-call boundary. |
| Cloud Run service has no HTTP listener | Medium | Open — redesign target | Replace with an appropriate job or authenticated service wrapper and test an actual deployment before advertising it as working. |
| Windows checkouts convert shell files to CRLF | Low | Fixed | `.gitattributes` forces LF and CI rejects CRLF shell scripts. |
| Missing vulnerability reporting policy | Low | Fixed locally | `SECURITY.md`. |
| Incorrect Render/Replit repository URLs and mutable-version claims | Low | Fixed locally | Platform documentation now references `atbash-sandbox` and exact CLI version. |
| Node `NODE_OPTIONS` preload could forge CLI output | High | Fixed and runtime-tested | `atbash-safe` clears `NODE_OPTIONS`/`NODE_PATH`, invokes a fixed Node binary and fixed CLI script, and replaces the public `atbash` symlink. |
| PATH shadowing could replace the Node interpreter | High | Fixed and runtime-tested | Hardened launcher bypasses `/usr/bin/env node`; forged `node` earlier produced a fake `ALLOW`, while the fixed image returns the real CLI version. |
| Base image/SDK ABI mismatch | High / availability | Fixed and build-tested | Alpine/musl could not load the published SDK native binding. Runtime now uses digest-pinned Debian Bookworm slim (glibc). |
| Privileged SUID/SGID utilities remained in image | Medium | Fixed and runtime-tested | Build strips all SUID/SGID bits; final scan finds none. |
| Malformed existing config continued after jq failure | Medium | Fixed and runtime-tested | Entrypoint removes temporary output and exits `2` rather than continuing to key generation. |

## Verification performed

- Git-history secret scan with Gitleaks: no leaks in 11 commits.
- npm production dependency audit for `@atbash/cli@0.5.8`: 0 known
  vulnerabilities across 56 resolved dependencies.
- Prehook unit tests cover valid verdicts, malformed/empty responses, timeout,
  process failure, missing dependencies, and explicit demo-only fail-open mode.
- Entrypoint tests cover key validation, mode-0600 persistence, and removal from
  the child environment.
- Shell syntax and Compose rendering are tested locally and in CI.
- Docker base manifest digest was resolved directly from Docker Hub.
- A no-cache Docker build completed and loaded `@atbash/cli@0.5.8` successfully.
- Docker Scout found 0 critical/high/medium/low vulnerabilities in 192 packages.
- Hardened runtime assertions verified non-root UID, empty capabilities,
  `NoNewPrivs: 1`, read-only root filesystem, mode-0600 config, CPU/memory/PID
  limits, and removal of npm/npx and SUID/SGID bits.
- Red-team injection probes proved the original CLI was forgeable through both
  `NODE_OPTIONS` and PATH-based `node` shadowing; both probes fail against the
  hardened launcher.
- Compose end-to-end runtime checks pass for non-root UID, empty capabilities,
  no-new-privileges, read-only root filesystem, PID limit, and secret removal.
- A live egress probe reached `https://example.com` with HTTP 200, confirming
  unrestricted Internet egress remains an open high-severity deployment issue.
  The tested metadata address did not respond, but provider-level metadata
  blocking must still be explicit rather than assumed from this result.

## Release blockers outside this worktree

1. Enable branch protection/rulesets and make the security workflow required.
2. Configure private vulnerability reporting and verify the `SECURITY.md`
   contact path.
3. Enforce runtime egress allowlists and metadata-service blocking per target.
4. Replace or validate the Cloud Run target end to end.
5. Implement signed deterministic local policy bundles before claiming offline
   enforcement; until then judge failure remains fail-closed.
6. Move production policy enforcement out of the user-controlled Bash shell.
7. Image runtime and vulnerability tests passed on Docker Desktop during this
   review; repeat them in required CI for every change.

## Release acceptance criteria

- No unfixed high/critical image vulnerabilities without written risk
  acceptance.
- All required CI checks pass on a clean checkout.
- Only immutable dependency/image references are deployed.
- Judge outage cannot produce an implicit `ALLOW`.
- A child process cannot inherit a reusable agent key.
- Runtime can reach approved Atbash dependencies but not arbitrary Internet or
  cloud metadata endpoints.
- Every advertised platform has a recorded deployment and teardown test.
- Production enforcement cannot be disabled by changing shell state.

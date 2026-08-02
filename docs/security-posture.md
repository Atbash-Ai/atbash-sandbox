# Security posture

This is a reference for what the sandbox templates do to keep your test
environment locked down, and where each control lives.

## Threat model

The sandbox is meant for **untrusted experimentation** — running the atbash
CLI, submitting weird payloads to `atbash judge`, and inviting the SDK's
secret-redaction and memory-scan paths to see them. The defenses below
exist so a bad day inside the sandbox does not turn into a bad day for the
host.

Out of scope: defending the atbash service itself (that is the service's
problem), defending against malicious atbash CLI binaries (we pin a known
version), defending against a malicious cloud provider.

## Controls

### Process identity

- Container runs as UID/GID **10001**, not root.
- Implemented in the Dockerfile via `adduser -D -u 10001 -h /home/atbash atbash` +
  `USER atbash`.
- Enforced platform-by-platform:
  - Cloud Run: `securityContext.runAsNonRoot: true`, `runAsUser: 10001`.
  - Devcontainer: `"remoteUser": "atbash"`, `"containerUser": "atbash"`.
  - Docker Compose: inherits `USER` from the image.
  - Fly.io, Render: inherit `USER` from the image; platform has no override.
  - Replit: caveat — Replit's `runner` user is not root but is not
    container-level enforced. See `replit/README.md`.

### Filesystem

- **Read-only root filesystem** where the platform supports it (Docker
  Compose `read_only: true`, Cloud Run `readOnlyRootFilesystem: true`).
- **Writable scratch space** via `tmpfs` for `/tmp` and the atbash cache
  dir. Tmpfs evaporates on container stop.
- **No host bind mounts**. The closest exception is the devcontainer's
  `workspaceMount`, which is an anonymous Docker volume — not a host path.
- **No persistent volumes**. None of the platform manifests provision disks.

### Permissions on the atbash config

- `~/.config/atbash/` is mode `0700`.
- `~/.config/atbash/telemetry.json` is mode `0600`, created at image build
  time.
- The CLI's `atbash keygen` produces `~/.config/atbash/config.json` mode
  `0600`; documented in the SDK as a requirement (`atbash-sdk/src/opentel/telemetry.ts:7-9`).

### Secrets

- The agent key (`ATBASH_AGENT_KEY`) is **never** baked into the image,
  committed, or logged. The default flow generates a fresh keypair inside the
  running container. If a platform injects a key through the environment, the
  Docker entrypoint validates it, atomically writes it to the mode-`0600`
  config, and unsets it before starting the user command. The private half
  lives on the tmpfs config directory and dies with the container.
- If you prefer to provide your own key, each platform's secret store
  injects `ATBASH_AGENT_KEY` (and `ATBASH_ORG_NAME`) at runtime:
  - Fly.io → `fly secrets set`
  - Render → Environment (`sync: false`)
  - Devcontainer → create a disposable key from inside the Codespace; the
    template intentionally does not forward a host key into the environment.
  - Replit → Secrets panel
  - Cloud Run → Secret Manager (`secretKeyRef`)
- `.env` (used by `docker compose run --rm atbash`) is `.gitignore`d.

### Linux capabilities & privilege escalation

- `cap_drop: [ALL]` (Docker Compose, Devcontainer `runArgs`, Cloud Run
  `capabilities.drop: [ALL]`).
- `security_opt: ["no-new-privileges:true"]` on Docker Compose and the
  devcontainer `runArgs`.
- Cloud Run: `allowPrivilegeEscalation: false`.

### Network

- No public ports for shell-only platforms. `fly.toml` omits `[[services]]`;
  Render uses `type: pserv` (private service); Cloud Run sets
  `ingress: internal`.
- Egress is unrestricted by default; the CLI needs to reach the Atbash judge
  endpoint. Production deployments must add provider-specific DNS/firewall/VPC
  allowlists and block cloud metadata endpoints. The Cloud Run template marks
  VPC egress as private-ranges-only, but a connector/firewall design is still
  required before treating that as an allowlist.

### Supply chain

- The base image uses the Node 22 Debian Bookworm slim tag plus an immutable
  multi-platform manifest digest. Digest updates are intentional and reviewable.
- The atbash CLI is pinned to the exact `@atbash/cli@0.5.8` release via the
  `ATBASH_CLI_VERSION` build arg. Version bumps are intentional, not implicit.
- `npm install` is run with `--no-audit --no-fund --no-update-notifier` to
  avoid noisy egress at build time. Audit is run separately if desired
  (`npm audit --omit=dev` inside the container).
- No third-party shell scripts are piped from `curl`. The Dockerfile's
  `apk add` packages are the only network reach during build.

## Verifying the posture for yourself

Inside any running sandbox container:

```bash
whoami                                          # → atbash
id                                              # uid=10001 gid=10001
ls -ld ~/.config/atbash/                        # drwx------ atbash atbash
ls -l  ~/.config/atbash/telemetry.json          # -rw------- atbash atbash
cat /proc/1/status | grep NoNewPrivs            # NoNewPrivs: 1
capsh --print 2>/dev/null || grep CapEff /proc/self/status   # all dropped
touch /etc/test 2>&1                            # read-only: should fail
atbash --version                                # @atbash/cli@0.5.8
docker history atbash-sandbox:local             # no plaintext secrets
```

From the host, against a built image:

```bash
docker scout cves atbash-sandbox:local          # or: trivy image atbash-sandbox:local
docker inspect atbash-sandbox:local | jq '.[0].Config.User'   # "atbash"
```

## When to deviate

You may want to relax the posture in narrow cases:

- **Local development of a new feature** — comment out `read_only: true` in
  `docker-compose.yml` only if you also revert before committing.
- **Network captures** — add `cap_add: [NET_ADMIN]` for `tcpdump`. Document
  why in the PR.

If you find yourself needing more than one of these at the same time, you
have probably outgrown the sandbox and want a developer workstation, not
this repo's templates.

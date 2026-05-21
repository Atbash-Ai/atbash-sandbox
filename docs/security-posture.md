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
- Implemented in the Dockerfile via `useradd --system --uid 10001 atbash` +
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
  never committed, and never logged. The default flow generates a fresh
  keypair *inside* the running container via `atbash keygen` in
  `entrypoint.sh`; the private half lives only on the tmpfs config dir
  and dies with the container.
- If you prefer to provide your own key, each platform's secret store
  injects `ATBASH_AGENT_KEY` (and `ATBASH_ORG_NAME`) at runtime:
  - Fly.io → `fly secrets set`
  - Render → Environment (`sync: false`)
  - Devcontainer → Codespaces Secrets / VS Code remote env
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
- Egress is unrestricted; the CLI needs to reach the atbash judge endpoint
  and (optionally) the Honeycomb telemetry endpoint.

### Supply chain

- The base image is `node:20-bookworm-slim`, a Debian-based image pinned to
  Node 20 and refreshed by upstream.
- The atbash CLI is pinned to `@atbash/cli@0.3.18` via the
  `ATBASH_CLI_VERSION` build arg. Bumps are intentional, not implicit.
- `npm install` is run with `--no-audit --no-fund --no-update-notifier` to
  avoid noisy egress at build time. Audit is run separately if desired
  (`npm audit --omit=dev` inside the container).
- No third-party shell scripts are piped from `curl`. The Dockerfile's
  `apt-get` packages are the only network reach during build.

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
atbash --version                                # @atbash/cli@0.3.18
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

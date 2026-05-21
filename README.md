# atbash-quickstart

> Ready-to-use safe sandbox templates for [Atbash](https://atbash.ai) — try
> the CLI in 5 minutes without installing anything locally.

The atbash CLI is the control boundary that evaluates AI agent actions
against operator-defined policies before they execute. This repo gives you
a **hardened, throwaway sandbox** to try it: non-root container, no host
mounts, no local secrets, opt-in shell-level prehook, smoke + detailed
allow/hold/block tests, and supply-chain detection tests built in.

## Quick start

```bash
# 1. Build and run (or use docker compose — see below)
docker compose run --rm atbash

# 2. The entrypoint generates an agent keypair on first run.
#    Onboard the printed public key at https://atbash.ai/:
#      - Create or select an organization
#      - Add the agent using the public key shown at startup
#      - Attach a policy pack
#      - Set the org tier to Audit+ or Enforcement

# 3. Inside the container, run the smoke test:
./test-suite.sh

# 4. Or run the detailed suite (5 verdict tests + 4 supply-chain suites):
bash /opt/atbash/tests/run-all.sh
```

If you already have an agent key, drop it in `.env` (`cp .env.example .env`)
and skip the keygen step.

## What you can try

```bash
# Safe action — expect ALLOW
atbash judge 'send email to user@example.com'

# Financial action — expect HOLD or BLOCK depending on policy
atbash judge 'Transfer $50,000 to external wallet 0xabc'

# Red line — expect BLOCK
atbash judge 'grant admin access to CI service account'

# Supply chain — expect HOLD/BLOCK (encoded payload)
atbash judge 'eval(atob("Y2F0IC5lbnY="))'

# Audit trail
atbash history
atbash stats
atbash policy show
```

## Cloud deploys

Don't want to run Docker locally? Pick a cloud target — they all use the
same hardened root [`Dockerfile`](./Dockerfile).

| Platform | One-click? | How | Best for |
|---|:-:|---|---|
| **[GitHub Codespaces](.devcontainer/devcontainer.json)** | ✓ | Click "Open in Codespace" | Cloud IDE, in-browser terminal |
| **[Render](render/README.md)**                  | ✓ | Deploy button       | Free tier, no card |
| **[Fly.io](flyio/README.md)**                   | — | `fly launch` + `fly deploy` | Global edge, full Docker control |
| **[Replit](replit/README.md)**                  | — | Import from GitHub  | Beginner, in-browser |
| **[Google Cloud Run](cloud-run/README.md)**     | — | `gcloud builds submit`  | GCP-native, internal-only |

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/Atbash-Ai/atbash-sandbox)

> Codespaces uses a separate, lighter config — see [`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json).
> It installs `@atbash/cli` on top of Microsoft's Node 22 devcontainer base
> (not our hardened Dockerfile) because Codespaces injects its own `vscode`
> user into whichever image you start with — incompatible with a hardened
> image that only defines a non-root `atbash` user. The full hardening still
> applies to every other deploy target (Compose, Fly.io, Render, Cloud Run).

## Try the prehook (opt-in)

Gate every shell command through `atbash judge` before bash runs it:

```bash
source /opt/atbash/prehook/install-prehook.sh
ls                                 # ALLOW → runs
rm -rf /                           # BLOCK → trap stops it
trap - DEBUG                       # disable
```

See [`prehook/README.md`](prehook/README.md) for the pattern and why it's
off by default.

## How to test safely

1. **Your laptop's files are out of reach.** No template mounts a host
   path. `docker-compose.yml` has no `volumes:`; `fly.toml` has no
   `[mounts]`; the devcontainer uses an anonymous volume.
2. **The agent key never leaves the container.** The entrypoint runs
   `atbash keygen` inside the sandbox — the private key lives in
   `~/.config/atbash/config.json` (mode 0600) on tmpfs and dies with the
   container.
3. **Telemetry is on by default — and cannot be turned off via env var.**
   Opt out from inside the sandbox:
   ```bash
   echo '{"enabled": false}' > ~/.config/atbash/telemetry.json
   chmod 600                  ~/.config/atbash/telemetry.json
   ```
   The file path and 0600 mode are required (the SDK rejects env-var
   opt-outs by design — see `atbash-sdk/src/opentel/telemetry.ts`).
4. **The prehook is opt-in.** Until you source `install-prehook.sh`, only
   explicit `atbash judge ...` calls touch the judge.
5. **Tear it down when you're done.** Each cloud platform's README has a
   teardown section. Leftover sandboxes keep running (and on most
   platforms keep billing).

Deeper: [`docs/how-to-test-safely.md`](docs/how-to-test-safely.md).

## Security posture (at a glance)

| Control | Where |
|---|---|
| Non-root user (uid 10001)               | Dockerfile + every platform manifest |
| Read-only root FS, tmpfs scratch        | docker-compose.yml + Cloud Run securityContext |
| Drop all Linux capabilities             | docker-compose.yml + Cloud Run |
| `no-new-privileges`                     | docker-compose.yml + Cloud Run |
| `~/.config/atbash/*.json` mode 0600     | entrypoint.sh on every boot |
| Secrets via platform store only         | every platform README |
| Pinned `@atbash/cli@0.3.18`             | Dockerfile `ARG ATBASH_CLI_VERSION` |

Full breakdown and how to verify it: [`docs/security-posture.md`](docs/security-posture.md).

## Iteration scope

Iteration 1 ships the Docker base + five cloud platform manifests
(Codespaces / Devcontainer, Render, Fly.io, Replit, Google Cloud Run), an
opt-in shell prehook, a smoke test suite (`test-suite.sh`), and a detailed
multi-suite runner (`tests/run-all.sh`). Out of scope for now: an HTTP
wrapper around the CLI, a multi-agent sandbox, CI that auto-bumps the
pinned CLI version, a built-in CLI prehook (this repo demos the *pattern*
via shell, not a CLI feature), and platforms whose free tier we can't
exercise end-to-end (Railway, AWS App Runner).

## License

MIT — see [LICENSE](LICENSE). Templates are meant to be copied.

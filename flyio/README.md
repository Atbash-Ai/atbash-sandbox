# Fly.io

Fly.io has no one-click deploy button, so this is a two-command path. Both
commands run from your laptop — you do not need to install the atbash CLI.

## Prerequisites

- `flyctl` ([install](https://fly.io/docs/flyctl/install/)) and `fly auth login`.

## Deploy in ~5 minutes

```bash
# 1. From the root of this repo:
cd flyio
fly launch --copy-config --no-deploy --name your-atbash-sandbox

# 2. Inject secrets (never committed to git):
fly secrets set ATBASH_AGENT_KEY=...   ATBASH_ORG_NAME=...

# 3. Deploy and connect:
fly deploy
fly ssh console
```

Inside the shell:

```bash
atbash whoami
atbash judge '{"action":"list_dir","path":"."}'
```

## Security posture on Fly.io

| Requirement              | How it's enforced on Fly.io                                              |
|--------------------------|---------------------------------------------------------------------------|
| Non-root user            | `USER atbash` in the Dockerfile is honored by Fly Machines.               |
| Config permissions 600   | Set at image build time; persists across restarts.                        |
| No host mounts           | No `[mounts]` section in `fly.toml`; no host filesystem accessible.       |
| No local secrets         | `fly secrets set` stores them in Fly's secret store, injected as env at runtime. |
| No public ports          | No `[[services]]` block in `fly.toml` — VM has no inbound network surface. |
| Pinned CLI version       | `ATBASH_CLI_VERSION` build arg in the Dockerfile (currently `latest`).    |

## Teardown

```bash
fly apps destroy your-atbash-sandbox
```

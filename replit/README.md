# Replit

Replit gives you a browser-based shell with no install required. The trade-off
vs. the other targets: Replit's runtime is **not** as locked-down as
Docker/Fly/Cloud Run. We document the caveat and still ship a working
template.

## Deploy in ~5 minutes

1. Open https://replit.com → **Import from GitHub** →
   `https://github.com/Atbash-Ai/atbash-quickstart`.
2. In the Replit UI, click the **Secrets** (🔒) tab. Add:
   - `ATBASH_AGENT_KEY`
   - `ATBASH_ORG_NAME`
3. Click **Run**. The shell will install `@atbash/cli` on first boot, then
   land you at a prompt with `atbash` on `PATH`.

```bash
atbash --version
atbash judge '{"action":"list_dir","path":"."}'
```

## Security posture on Replit

| Requirement              | How it's enforced on Replit                                              |
|--------------------------|---------------------------------------------------------------------------|
| Non-root user            | **Caveat:** Replit runs your code as the `runner` user, which is not root, but the sandbox cannot enforce `USER` from a Dockerfile. The lockdown is provided by Replit's broader sandboxing (firecracker-based), not by `runAs*` configuration. |
| Config permissions 600   | Applied in the boot command (see `.replit` `run`).                        |
| No host mounts           | Replit filesystems are per-Repl and isolated by design.                   |
| No local secrets         | Use Replit **Secrets** (encrypted at rest). Never paste keys into the editor. |
| Pinned CLI version       | The `run` command installs a pinned version on boot (`@atbash/cli@0.3.18`). |

## When NOT to use Replit

If you are testing prehook behavior, supply-chain detection, or anything where
the host's process isolation matters, prefer Docker Compose, Fly.io, or
Cloud Run. Replit's environment is more permissive than a hardened container.

## Teardown

Delete the Repl from your Replit account.

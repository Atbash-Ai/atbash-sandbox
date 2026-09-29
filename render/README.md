# Render

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https%3A%2F%2Fgithub.com%2FAtbash-Ai%2Fatbash-quickstart)

The button uses the [`render.yaml`](./render.yaml) blueprint at the repo
root path resolution.

## Deploy in ~5 minutes

1. Click **Deploy to Render**.
2. Authorize the Render GitHub App on `Atbash-Ai/atbash-quickstart`. (Render
   supports both public and private repos, but installing the App is required.)
3. After the service is created, open its **Environment** tab and add
   `ATBASH_AGENT_KEY` and `ATBASH_ORG_NAME` as secret environment variables.
   `render.yaml` declares no env vars, so the blueprint does not prompt for
   them and never holds a value; without a key the entrypoint generates one.
4. After the build finishes, open the service in the Render dashboard and
   click the **Shell** tab to get a terminal.

```bash
atbash whoami
atbash judge '{"action":"list_dir","path":"."}'
```

## Security posture on Render

| Requirement              | How it's enforced on Render                                              |
|--------------------------|---------------------------------------------------------------------------|
| Non-root user            | `USER atbash` in the Dockerfile.                                          |
| Config permissions 600   | Set at image build time.                                                  |
| No host mounts           | No `disk:` section in `render.yaml` — no persistent volume.               |
| No local secrets         | `render.yaml` declares no env vars at all; the key and org are set in the dashboard's Environment tab, never in the repo. |
| No public network        | `type: pserv` (private service) — no inbound HTTP.                        |
| Pinned CLI version       | `ATBASH_CLI_VERSION` build arg in the Dockerfile (currently `0.7.4`).     |

## Teardown

Delete the service from the Render dashboard (Service → Settings → Delete Service).

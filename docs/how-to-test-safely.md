# How to test Atbash safely

You can poke at `atbash judge` for an afternoon and walk away with no trace
on your laptop. This document tells you why that is true and what to keep an
eye on.

## The mental model

Every sandbox in this repo is a single short-lived container:

1. The entrypoint script runs `atbash keygen` on first boot and prints the
   agent's public key. You onboard that public key at https://atbash.ai/
   (no private key ever leaves the sandbox). Alternatively, inject your
   own `ATBASH_AGENT_KEY` via the platform's secret store (Fly secrets,
   Render env, Codespaces Secrets, Replit Secrets, or Cloud Run Secret
   Manager) and the entrypoint skips keygen.
2. The container runs as the non-root `atbash` user.
3. The container has no mount into your laptop's filesystem.
4. When you tear it down, the container, its config files, and any local
   state (including the generated agent key) vanish.

The atbash service itself sees your judge submissions — those are stored on
the Chromia chain by design. **The sandbox is local-side isolation; it does
not affect what the judge or the immutable audit log do with your queries.**

## What a "safe" test session looks like

1. Pick a platform and deploy the sandbox (5 min, see root README).
2. Open a shell:

   ```bash
   fly ssh console                     # Fly.io
   # (Render dashboard "Shell" tab)    # Render
   # (Codespaces integrated terminal)  # Codespaces
   ```

3. Try one of each verdict so you can see the shape of the responses:

   ```bash
   atbash judge 'send email to user@example.com'                  # → ALLOW
   atbash judge 'Transfer $500 to external account'               # → HOLD
   atbash judge 'grant admin access to CI service account'        # → BLOCK
   ```

4. Run the full suite:

   ```bash
   bash /opt/atbash/tests/run-all.sh
   ```

5. (Optional) try the prehook demo:

   ```bash
   source /opt/atbash/prehook/install-prehook.sh
   # Every shell command is now gated through 'atbash judge'.
   ls
   rm -rf /
   ```

6. **Tear down.** This is the actual safety guarantee — leftover sandboxes
   keep running and (on most platforms) keep billing. Each platform's
   `README.md` includes a teardown section.

## Common safety questions

### Can the sandbox read files off my laptop?

No. None of the templates mount a host path. `docker-compose.yml` has no
`volumes:` block; `fly.toml` has no `[mounts]`; the devcontainer config
sets `workspaceMount` to a fresh anonymous volume; cloud runtimes don't
allow host mounts at all.

### What about the agent key — is it in the image?

No. The image is built without secrets. The entrypoint runs `atbash keygen`
on first boot, *inside* the container, and the resulting private key lives
in `~/.config/atbash/config.json` on a tmpfs that evaporates when the
container stops. `docker history` on the built image will not show any
key. The image is safe to mirror or share.

If you want to provide your own key instead of using the on-first-run
keygen, set `ATBASH_AGENT_KEY` via the platform's secret store (Fly
secrets, Render env, Codespaces Secrets, Replit Secrets, Cloud Run Secret
Manager). The entrypoint detects the env var and skips keygen.

### Is telemetry on?

Yes, by default. Atbash uses telemetry to track adoption and detect product
issues. It is **not** controlled by an environment variable — that is a
deliberate hardening choice (see `atbash-sdk/src/opentel/telemetry.ts`).
Opt out from inside the sandbox:

```bash
echo '{"enabled": false}' > ~/.config/atbash/telemetry.json
chmod 600                  ~/.config/atbash/telemetry.json
```

You will need to restart the shell (or re-attach to the container) for
the change to take effect.

### Can the prehook block me out of my own shell?

It can, if you enable it and try a command the policy blocks. To recover,
exit the shell and re-attach without sourcing the install script. Or use a
new shell on the same container (`bash --noprofile --norc`) and run
`trap - DEBUG`.

### What if I want to test against my own organization without affecting it?

Generate a throwaway agent key just for the sandbox (`atbash keygen`
from another machine, then export the printed key) and use a non-production
`ATBASH_ORG_NAME`. The judge records every action on-chain, so a separate
agent key keeps the test traffic identifiable.

## What is NOT safe to do here

- **Do not** paste your production agent key into a Replit, Codespace, or
  Render env field where you intend to leave the sandbox running publicly
  for someone else to inspect. Secret stores are encrypted at rest; their
  values are still readable by anyone with project access.
- **Do not** test against your real production org without a low-traffic
  policy pack — `BLOCK` verdicts may trigger the Enforcement tier on your
  agent, which can lock out other systems sharing that key.
- **Do not** disable the read-only root filesystem in `docker-compose.yml`
  unless you understand why it was there. It exists to make the sandbox
  forensically simpler — anything that gets written goes to tmpfs and dies
  with the container.

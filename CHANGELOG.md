# Changelog

All notable changes to the Atbash sandbox. Each release section becomes the
message of that release's commit in this repository.

## 1.0.0 - 2026-11-19

- The opt-in prehook fails closed: it runs a command only on an `allow`
  verdict, and denies it when the judge is unreachable, returns no verdict, or
  returns anything else (`ERROR`, `UNKNOWN`, an empty reply).
- The prehook no longer exempts its own recursion guard or prefix-matched
  commands, so a gated command cannot switch the gate off.
- The image is based on Debian bookworm-slim instead of Alpine, so the CLI's
  native SDK loads (`atbash --version` failed on Alpine).
- `@atbash/cli` 0.7.6 and `@atbash/sdk` 0.9.2 are installed from a committed
  lockfile with `npm ci --ignore-scripts`, and the build fails if any other
  version resolves. Platform manifests pin the same CLI version instead of
  `latest`.
- The image runs as a non-root user (uid 10001) under tini, and the
  entrypoint, prehook and scenarios are root-owned so the runtime user cannot
  rewrite them.
- The detailed live-judge scenarios moved from `/opt/atbash/tests` to
  `/opt/atbash/scenarios`: run `bash /opt/atbash/scenarios/run-all.sh`.

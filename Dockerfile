# Atbash CLI sandbox — isolated test environment.
#
# Build:  docker build -t atbash-sandbox .
# Run:    docker run -it --rm atbash-sandbox
#
# Or with docker-compose (recommended — adds read-only FS, cap_drop, etc.):
#   docker compose run --rm atbash

FROM node:22-alpine

ARG ATBASH_CLI_VERSION=0.3.18

ENV NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_AUDIT=false

# bash for the opt-in prehook (DEBUG trap is bash-specific);
# tini for PID-1 signal handling; jq is handy for parsing judge JSON output.
RUN apk add --no-cache bash tini jq ca-certificates

# Non-root user (reviewer requirement). Explicit UID so platform manifests
# (Cloud Run securityContext, devcontainer runArgs) can reference it.
RUN adduser -D -u 10001 -h /home/atbash atbash

# Install the CLI globally — pinned version, not @latest.
RUN npm install -g "@atbash/cli@${ATBASH_CLI_VERSION}" \
 && npm cache clean --force \
 && atbash --version

USER atbash
WORKDIR /home/atbash

# Config dir for atbash CLI; entrypoint.sh ensures 0700/0600 perms at runtime.
# When docker-compose mounts this path as tmpfs (read-only root FS pattern),
# entrypoint.sh re-seeds the dir on each boot from the templates in /opt/atbash.
RUN mkdir -p /home/atbash/.config/atbash \
 && chmod 0700 /home/atbash/.config/atbash

# Telemetry seed — copied into ~/.config/atbash/telemetry.json by entrypoint.sh
# on every boot. The Atbash SDK only disables telemetry via this file
# (env vars cannot — see atbash-sdk/src/opentel/telemetry.ts:9).
COPY --chown=atbash:atbash telemetry/telemetry.json /opt/atbash/telemetry.json

# Friendly entrypoint that auto-generates an agent keypair on first run
# (so users can onboard at atbash.ai without copy-pasting a key around).
COPY --chown=atbash:atbash entrypoint.sh /home/atbash/entrypoint.sh

# Smoke test suite — single-file demo run via ./test-suite.sh after onboarding.
COPY --chown=atbash:atbash test-suite.sh /home/atbash/test-suite.sh

# Detailed multi-suite tests (5 verdicts + 4 supply-chain categories) at
# /opt/atbash/tests for users who want a more thorough run.
COPY --chown=atbash:atbash tests/ /opt/atbash/tests/

# Opt-in shell-level prehook demonstration (DEBUG trap pattern).
COPY --chown=atbash:atbash prehook/ /opt/atbash/prehook/

USER root
RUN chmod 0755 /home/atbash/entrypoint.sh /home/atbash/test-suite.sh \
               /opt/atbash/tests/*.sh /opt/atbash/tests/supply-chain/*.sh \
               /opt/atbash/prehook/*.sh
USER atbash

ENTRYPOINT ["/sbin/tini", "--", "/home/atbash/entrypoint.sh"]
CMD ["sh"]

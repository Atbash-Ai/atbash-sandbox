# Atbash CLI sandbox — isolated test environment.
#
# Build:  docker build -t atbash-sandbox .
# Run:    docker run -it --rm atbash-sandbox
#
# Or with docker-compose (recommended — adds read-only FS, cap_drop, etc.):
#   docker compose run --rm atbash

FROM node:22-bookworm-slim@sha256:f32b81066cde10a75dbac96646099533316d94bac4150c55da1636e1f0ffdc46

ARG ATBASH_CLI_VERSION=0.5.8
ARG ATBASH_CLI_INTEGRITY=sha512-PFJiDgtAzdHb7QNMdc78dyhkH70yo2CutSUOyXHS8F1+eCUJNPJBNaEEamd7eo5/4srSjFnZV/6M6LFzdrQ6rA==
ARG NPM_VERSION=12.0.2

ENV NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_AUDIT=false

# bash for the opt-in prehook (DEBUG trap is bash-specific); tini for PID-1
# signal handling; jq is used for strict judge/config JSON parsing.
RUN apt-get update \
 && apt-get install -y --no-install-recommends bash tini jq ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# A patched npm is used only as a build tool. It is removed after the verified
# CLI installation so package-management internals do not remain in the
# runtime attack surface.
RUN npm install -g "npm@${NPM_VERSION}" \
 && npm --version

# Non-root user (reviewer requirement). Explicit UID so platform manifests
# (Cloud Run securityContext, devcontainer runArgs) can reference it.
RUN useradd --uid 10001 --create-home --home-dir /home/atbash --shell /bin/bash atbash

# Install the exact CLI release and verify the registry's expected integrity
# before npm executes any package lifecycle scripts.
RUN npm pack "@atbash/cli@${ATBASH_CLI_VERSION}" --silent \
 && TARBALL="atbash-cli-${ATBASH_CLI_VERSION}.tgz" \
 && ACTUAL_INTEGRITY="$(node -e "const fs=require('fs'),c=require('crypto');process.stdout.write('sha512-'+c.createHash('sha512').update(fs.readFileSync(process.argv[1])).digest('base64'))" "$TARBALL")" \
 && test "$ACTUAL_INTEGRITY" = "$ATBASH_CLI_INTEGRITY" \
 && npm install -g --ignore-scripts "./$TARBALL" \
 && rm -f "$TARBALL" \
 && npm cache clean --force \
 && atbash --version \
 && rm -rf /usr/local/lib/node_modules/npm \
 && rm -f /usr/local/bin/npm /usr/local/bin/npx

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

# Hardened CLI launcher: fixed Node path and NODE_OPTIONS/NODE_PATH removal.
COPY --chown=root:root atbash-safe /usr/local/bin/atbash-safe

USER root
RUN chmod 0755 /home/atbash/entrypoint.sh /home/atbash/test-suite.sh \
               /opt/atbash/tests/*.sh /opt/atbash/tests/supply-chain/*.sh \
               /opt/atbash/prehook/*.sh /usr/local/bin/atbash-safe \
 && ln -sf /usr/local/bin/atbash-safe /usr/local/bin/atbash \
 && find / -xdev -type f \( -perm -4000 -o -perm -2000 \) -exec chmod a-s {} +
USER atbash

ENV ATBASH_CLI_BIN=/usr/local/bin/atbash-safe

ENTRYPOINT ["/usr/bin/tini", "--", "/home/atbash/entrypoint.sh"]
CMD ["sh"]

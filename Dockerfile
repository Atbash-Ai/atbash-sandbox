# Atbash CLI sandbox — isolated test environment.
#
# Build:  docker build -t atbash-sandbox .
# Run:    docker run -it --rm atbash-sandbox
#
# Or with docker-compose (recommended — adds read-only FS, cap_drop, etc.):
#   docker compose run --rm atbash

# Debian (glibc), not Alpine (musl): every published @atbash/sdk-linux-x64-musl
# (0.8.0 through 0.9.1) is a glibc binary (readelf: NEEDED libc.so.6 and
# ld-linux-x86-64.so.2, GLIBC_2.34 symbol versions), so on Alpine the CLI
# cannot load its native SDK and `atbash --version` fails. Stay on glibc until
# a real musl build is published.
#
# Pinned by the multi-platform index digest so a re-pushed tag cannot change
# the base without a diff. Verified 2026-09-28 with
# `docker buildx imagetools inspect node:22-bookworm-slim`
# (linux/amd64 manifest sha256:25330af3531fb5e23318554a0aa911125b6e91b1b777edf7655501d207c067a2).
FROM node:22-bookworm-slim@sha256:43ac6c60b8f89723f746e8a92ce91abd5017e627ce1ddfe4238355d3a30b772c

# The CLI version the committed lockfile (cli/package-lock.json) installs.
# The install below fails the build if the lock resolves any other version, so
# this arg, docker-compose.yml and the lock cannot drift apart silently. To
# upgrade: bump cli/package.json, regenerate the lock, bump this line.
ARG ATBASH_CLI_VERSION=0.7.4

ENV NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_AUDIT=false

# bash for the opt-in prehook (DEBUG trap is bash-specific);
# tini for PID-1 signal handling; jq is handy for parsing judge JSON output.
RUN apt-get update \
 && apt-get install --yes --no-install-recommends bash tini jq ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Non-root user (reviewer requirement). Explicit UID/GID so platform manifests
# (Cloud Run securityContext, devcontainer runArgs) can reference it.
RUN groupadd --gid 10001 atbash \
 && useradd --uid 10001 --gid 10001 --create-home --home-dir /home/atbash \
            --shell /bin/sh atbash

# Install the CLI from the committed lockfile, not from a version range.
# `npm install -g @atbash/cli@X` pins only the top package: its @atbash/sdk
# (^0.9.0) and about 60 transitive packages float to whatever the registry serves at
# build time. `npm ci` installs exactly the tree in cli/package-lock.json, with
# every tarball checked against its sha512 integrity hash, and fails if
# package.json and the lock disagree.
# This layer runs as root, so --ignore-scripts matters: without it a
# preinstall/postinstall from any package in the tree gets root code execution
# in the builder. The CLI and SDK ship prebuilt JS and native binaries and need
# no install scripts (the lock records hasInstallScript for none of them).
COPY cli/package.json cli/package-lock.json /opt/atbash/cli/
WORKDIR /opt/atbash/cli
RUN npm ci --ignore-scripts --omit=dev \
 && npm cache clean --force \
 && test "$(node -p "require('./node_modules/@atbash/cli/package.json').version")" = "${ATBASH_CLI_VERSION}" \
 && ln -s /opt/atbash/cli/node_modules/.bin/atbash /usr/local/bin/atbash \
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

ENTRYPOINT ["/usr/bin/tini", "--", "/home/atbash/entrypoint.sh"]
CMD ["sh"]

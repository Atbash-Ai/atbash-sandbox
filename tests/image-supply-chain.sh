#!/usr/bin/env bash
# Static supply-chain checks on the image build inputs.
#
# The Dockerfile comment said "pinned version, not @latest" while the build arg
# defaulted to `latest` and docker-compose passed `latest` explicitly, so every
# build resolved whatever the registry served at that moment — no version to
# review, no lockfile, no integrity pin. The install also ran as root with
# lifecycle scripts enabled, so one hijacked publish of @atbash/cli meant root
# code execution in every builder. docs/security-posture.md asserted the
# control existed, which is worse than not claiming it.
#
# Repo-checkout check: it reads the Dockerfile and compose file, which are not
# copied into the image, so CI runs it rather than tests/run-all.sh.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

fails=0
ok()  { printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad() { printf '  \033[31mfail\033[0m %s\n' "$1"; fails=$((fails + 1)); }

for f in Dockerfile docker-compose.yml docs/security-posture.md; do
  [ -f "$ROOT/$f" ] || { bad "missing $f"; printf '\033[31mFAIL\033[0m image-supply-chain (%s)\n' "$fails"; exit 1; }
done

# 1. The CLI version is a concrete release, not a floating tag.
version=$(sed -n 's/^ARG ATBASH_CLI_VERSION=\(.*\)$/\1/p' "$ROOT/Dockerfile" | tr -d '"' | tr -d '\r')
if printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  ok "Dockerfile ARG ATBASH_CLI_VERSION=$version is a concrete version"
else
  bad "Dockerfile ARG ATBASH_CLI_VERSION='$version' is not a concrete version"
fi

# 2. Lifecycle scripts do not run during the global (root) install.
if grep -q 'npm install -g' "$ROOT/Dockerfile" && ! grep -q 'npm install -g.*--ignore-scripts' "$ROOT/Dockerfile"; then
  bad "global npm install runs package lifecycle scripts (add --ignore-scripts)"
else
  ok "global npm install passes --ignore-scripts"
fi

# 3. Compose does not override the pin with a floating tag.
compose_version=$(sed -n 's/.*ATBASH_CLI_VERSION:[[:space:]]*//p' "$ROOT/docker-compose.yml" | tr -d '"' | tr -d '\r' | head -1)
if [ -z "$compose_version" ]; then
  ok "docker-compose.yml inherits the Dockerfile pin"
elif [ "$compose_version" = "$version" ]; then
  ok "docker-compose.yml passes the same pin ($compose_version)"
else
  bad "docker-compose.yml passes ATBASH_CLI_VERSION='$compose_version', Dockerfile pins '$version'"
fi

# 4. The security doc describes the pin that actually exists.
if grep -q '@atbash/cli@latest' "$ROOT/docs/security-posture.md"; then
  bad "docs/security-posture.md still claims the CLI is pinned to @atbash/cli@latest"
elif grep -q "@atbash/cli@$version" "$ROOT/docs/security-posture.md"; then
  ok "docs/security-posture.md names the pinned version $version"
else
  bad "docs/security-posture.md does not name the pinned version $version"
fi

if [[ "$fails" -eq 0 ]]; then
  printf '\033[32mPASS\033[0m image-supply-chain\n'
  exit 0
fi
printf '\033[31mFAIL\033[0m image-supply-chain (%s)\n' "$fails"
exit 1

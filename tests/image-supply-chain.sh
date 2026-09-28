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
# Pinning only @atbash/cli was still not a pin: its @atbash/sdk (^0.9.0) and
# the rest of the tree floated. The image now installs from the committed
# cli/package-lock.json with `npm ci`, and these checks hold it there.
#
# Repo-checkout check: it reads the Dockerfile, compose file and lockfile,
# which are not copied into the image, so CI runs it rather than
# tests/run-all.sh. Needs jq.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

fails=0
ok()  { printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad() { printf '  \033[31mfail\033[0m %s\n' "$1"; fails=$((fails + 1)); }

# Instruction text without comment lines, so a comment that merely mentions a
# command cannot satisfy (or trip) a check. Dockerfile/TOML use '#', JSONC '//'.
code_lines() { grep -Ev '^[[:space:]]*(#|//)' "$1" | tr -d '\r'; }

for f in Dockerfile docker-compose.yml docs/security-posture.md cli/package.json cli/package-lock.json; do
  [ -f "$ROOT/$f" ] || { bad "missing $f"; printf '\033[31mFAIL\033[0m image-supply-chain (%s)\n' "$fails"; exit 1; }
done
command -v jq >/dev/null 2>&1 || { bad "jq is required to read cli/package-lock.json"; printf '\033[31mFAIL\033[0m image-supply-chain (%s)\n' "$fails"; exit 1; }

# 1. The CLI version is a concrete release, not a floating tag.
version=$(sed -n 's/^ARG ATBASH_CLI_VERSION=\(.*\)$/\1/p' "$ROOT/Dockerfile" | tr -d '"' | tr -d '\r')
if printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  ok "Dockerfile ARG ATBASH_CLI_VERSION=$version is a concrete version"
else
  bad "Dockerfile ARG ATBASH_CLI_VERSION='$version' is not a concrete version"
fi

# 2. Every base image is pinned by digest, not only by tag.
from_lines=$(code_lines "$ROOT/Dockerfile" | grep -Ei '^[[:space:]]*FROM[[:space:]]')
if [ -z "$from_lines" ]; then
  bad "Dockerfile has no FROM line"
elif printf '%s\n' "$from_lines" | grep -Evq '^[[:space:]]*FROM[[:space:]]+[^[:space:]]+@sha256:[0-9a-f]{64}([[:space:]]|$)'; then
  bad "a Dockerfile FROM line is not pinned by @sha256 digest: $(printf '%s\n' "$from_lines" | grep -Ev '@sha256:[0-9a-f]{64}' | head -1)"
else
  ok "every Dockerfile FROM line is pinned by @sha256 digest"
fi

# 3. The committed lockfile pins the whole CLI tree.
pkg_spec=$(jq -r '.dependencies["@atbash/cli"] // empty' "$ROOT/cli/package.json")
if [ "$pkg_spec" = "$version" ]; then
  ok "cli/package.json depends on @atbash/cli exactly $version"
else
  bad "cli/package.json depends on @atbash/cli '$pkg_spec', want exactly '$version' (no range)"
fi
lock_version=$(jq -r '.lockfileVersion // 0' "$ROOT/cli/package-lock.json")
if [ "$lock_version" -ge 2 ] 2>/dev/null; then
  ok "cli/package-lock.json is lockfileVersion $lock_version"
else
  bad "cli/package-lock.json lockfileVersion '$lock_version' (need >= 2, with a packages map)"
fi
locked_cli=$(jq -r '.packages["node_modules/@atbash/cli"].version // empty' "$ROOT/cli/package-lock.json")
if [ "$locked_cli" = "$version" ]; then
  ok "cli/package-lock.json locks @atbash/cli $locked_cli"
else
  bad "cli/package-lock.json locks @atbash/cli '$locked_cli', Dockerfile pins '$version'"
fi
entries=$(jq '[.packages | to_entries[] | select(.key != "")] | length' "$ROOT/cli/package-lock.json")
unhashed=$(jq -r '.packages | to_entries[] | select(.key != "" and (.value.link | not))
  | select(((.value.integrity // "") | startswith("sha512-") | not)
        or ((.value.resolved // "") | startswith("https://registry.npmjs.org/") | not))
  | .key' "$ROOT/cli/package-lock.json")
if [ "$entries" -gt 0 ] && [ -z "$unhashed" ]; then
  ok "all $entries locked packages carry a sha512 integrity hash and a registry.npmjs.org tarball"
else
  bad "locked packages without sha512 integrity or with a non-registry source: $(printf '%s' "$unhashed" | tr '\n' ' ')"
fi

# 4. The image installs from that lockfile, with lifecycle scripts off.
docker_code=$(code_lines "$ROOT/Dockerfile")
if printf '%s\n' "$docker_code" | grep -Eq '^COPY[[:space:]].*cli/package\.json[[:space:]]+cli/package-lock\.json[[:space:]]' \
   && printf '%s\n' "$docker_code" | grep -Eq '(^RUN|&&)[[:space:]]*npm[[:space:]]+ci[[:space:]].*--ignore-scripts'; then
  ok "Dockerfile copies cli/package-lock.json and installs with npm ci --ignore-scripts"
else
  bad "Dockerfile does not install from cli/package-lock.json with npm ci --ignore-scripts"
fi
if printf '%s\n' "$docker_code" | grep -Eq 'npm[[:space:]]+(install|i|add)([[:space:]]|$)'; then
  bad "Dockerfile also runs npm install, which resolves ranges instead of the lock"
else
  ok "Dockerfile has no npm install beside the locked npm ci"
fi

# 5. Nothing runs the CLI as root at build time. Everything before the first
#    `USER atbash` runs as root; an `atbash` command there executes the SDK's
#    native binary with root privileges in the builder. Matches `atbash` in
#    command position (after RUN, &&, ||, ;, |, optionally via exec), not as
#    an argument such as `useradd ... atbash` or a path ending in /atbash.
invoke_re='(^[[:space:]]*RUN|&&|\|\||;|\|)[[:space:]]*(exec[[:space:]]+)?atbash([[:space:]]|$)'
user_re='^[[:space:]]*USER[[:space:]]+atbash([[:space:]]|$)'
pre_user=$(printf '%s\n' "$docker_code" | awk -v re="$user_re" '$0 ~ re { exit } { print }')
root_call=$(printf '%s\n' "$pre_user" | grep -E "$invoke_re" | head -1 | sed 's/^[[:space:]]*//')
if ! printf '%s\n' "$docker_code" | grep -Eq "$user_re"; then
  bad "Dockerfile never switches to USER atbash"
elif [ -n "$root_call" ]; then
  bad "Dockerfile runs atbash as root before the first USER atbash: $root_call"
else
  ok "no atbash invocation before the first USER atbash (the smoke check runs as the runtime user)"
fi

# 6. Compose does not override the pin with a floating tag.
compose_version=$(sed -n 's/.*ATBASH_CLI_VERSION:[[:space:]]*//p' "$ROOT/docker-compose.yml" | tr -d '"' | tr -d '\r' | head -1)
if [ -z "$compose_version" ]; then
  ok "docker-compose.yml inherits the Dockerfile pin"
elif [ "$compose_version" = "$version" ]; then
  ok "docker-compose.yml passes the same pin ($compose_version)"
else
  bad "docker-compose.yml passes ATBASH_CLI_VERSION='$compose_version', Dockerfile pins '$version'"
fi

# 7. The security doc describes the pin that actually exists.
if grep -q '@atbash/cli@latest' "$ROOT/docs/security-posture.md"; then
  bad "docs/security-posture.md still claims the CLI is pinned to @atbash/cli@latest"
elif grep -q "@atbash/cli@$version" "$ROOT/docs/security-posture.md" \
     && grep -q 'cli/package-lock.json' "$ROOT/docs/security-posture.md"; then
  ok "docs/security-posture.md names the pinned version $version and the lockfile"
else
  bad "docs/security-posture.md does not name the pinned version $version and cli/package-lock.json"
fi

if [[ "$fails" -eq 0 ]]; then
  printf '\033[32mPASS\033[0m image-supply-chain\n'
  exit 0
fi
printf '\033[31mFAIL\033[0m image-supply-chain (%s)\n' "$fails"
exit 1

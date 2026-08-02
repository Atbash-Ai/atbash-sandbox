#!/usr/bin/env bash
# Local tests for entrypoint credential handling and validation.

set -uo pipefail

ROOT="${ATBASH_TEST_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat > "$TMP/bin/jq" <<'MOCK'
#!/usr/bin/env bash
args=("$@")
key=""
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "--arg" ]]; then
    key="${args[$((i+2))],,}"
  fi
done

if [[ " $* " == *" -e "* ]]; then
  value=$(tr -d '[:space:]' < "${args[-1]}" | sed -n 's/.*"agentKey":"\([^"]*\)".*/\1/p')
  [[ ${#value} -eq 64 ]]
  exit
fi

if [[ " $* " == *" -r "* ]]; then
  tr -d '[:space:]' < "${args[-1]}" | sed -n 's/.*"agentKey":"\([^"]*\)".*/\1/p'
  exit 0
fi

if [[ " $* " != *" -n "* ]] && ! grep -q '^[[:space:]]*{' "${args[-1]}"; then
  exit 4
fi

printf '{"agentKey":"%s"}\n' "$key"
MOCK

cat > "$TMP/bin/atbash" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "keygen" ]]; then
  mkdir -p "$HOME/.config/atbash"
  printf '{"agentKey":"%064d"}\n' 0 > "$HOME/.config/atbash/config.json"
fi
MOCK
chmod +x "$TMP/bin/atbash" "$TMP/bin/jq"

pass=0
fail=0
record() {
  if "$@"; then
    printf 'ok   %s\n' "$name"
    pass=$((pass + 1))
  else
    printf 'fail %s\n' "$name"
    fail=$((fail + 1))
  fi
}

home="$TMP/valid"
mkdir -p "$home"
key="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
name="valid key is persisted and removed from child environment"
HOME="$home" PATH="$TMP/bin:$PATH" TEST_JQ="$TMP/bin/jq" \
  ATBASH_CLI_BIN="$TMP/bin/atbash" ATBASH_AGENT_KEY="$key" \
  sh "$ROOT/entrypoint.sh" sh -c \
    'test -z "${ATBASH_AGENT_KEY+x}" && test "$("$TEST_JQ" -r .agentKey "$HOME/.config/atbash/config.json")" = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'
status=$?
record test "$status" -eq 0

name="config file mode check"
perm=$(stat -c '%a' "$home/.config/atbash/config.json" 2>/dev/null)
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
  # MSYS reports emulated Windows ACL modes; Linux CI asserts exact 0600.
  record test -n "$perm"
else
  record test "$perm" = 600
fi

home="$TMP/invalid"
mkdir -p "$home"
name="invalid key is rejected"
HOME="$home" PATH="$TMP/bin:$PATH" ATBASH_CLI_BIN="$TMP/bin/atbash" \
  ATBASH_AGENT_KEY="not-a-private-key" \
  sh "$ROOT/entrypoint.sh" true >/dev/null 2>&1
status=$?
record test "$status" -eq 2

home="$TMP/missing-launcher"
mkdir -p "$home"
name="missing hardened launcher is rejected"
HOME="$home" PATH="$TMP/bin:$PATH" ATBASH_CLI_BIN="$TMP/missing-atbash-safe" \
  sh "$ROOT/entrypoint.sh" true >/dev/null 2>&1
status=$?
record test "$status" -eq 2

home="$TMP/malformed"
mkdir -p "$home/.config/atbash"
printf 'not json\n' > "$home/.config/atbash/config.json"
name="malformed existing config is rejected"
HOME="$home" PATH="$TMP/bin:$PATH" ATBASH_CLI_BIN="$TMP/bin/atbash" \
  ATBASH_AGENT_KEY="$key" sh "$ROOT/entrypoint.sh" true >/dev/null 2>&1
status=$?
record test "$status" -eq 2

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]

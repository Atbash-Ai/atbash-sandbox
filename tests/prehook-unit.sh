#!/usr/bin/env bash
# Local unit tests for prehook verdict and availability behavior.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"

cat > "$TMP/bin/jq" <<'MOCK'
#!/usr/bin/env bash
if [[ " $* " == *" -nc "* ]]; then
  printf '{"action":"shell_command","cmd":"mocked"}\n'
  exit 0
fi
response=$(cat)
case "$response" in
  '{"verdict":"allow"}'|'{"verdict":"ALLOW"}') printf 'allow\n' ;;
  '{"verdict":"hold"}'|'{"verdict":"HOLD"}') printf 'hold\n' ;;
  '{"verdict":"block"}'|'{"verdict":"BLOCK"}') printf 'block\n' ;;
  *) exit 4 ;;
esac
MOCK

cat > "$TMP/bin/timeout" <<'MOCK'
#!/usr/bin/env bash
shift
exec "$@"
MOCK

cat > "$TMP/bin/atbash" <<'MOCK'
#!/usr/bin/env bash
case "${MOCK_JUDGE_MODE:-allow}" in
  allow|hold|block) printf '{"verdict":"%s"}\n' "$MOCK_JUDGE_MODE" ;;
  uppercase) printf '{"verdict":"ALLOW"}\n' ;;
  malformed) printf 'not-json\n' ;;
  unknown) printf '{"verdict":"maybe"}\n' ;;
  empty) : ;;
  error) exit 1 ;;
  timeout) exit 124 ;;
esac
MOCK

chmod +x "$TMP/bin/jq" "$TMP/bin/timeout" "$TMP/bin/atbash"

pass=0
fail=0

run_case() {
  local name="$1"
  local mode="$2"
  local fail_mode="$3"
  local expected="$4"
  local marker="$TMP/$name.executed"

  rm -f "$marker"
  PATH="$TMP/bin:$PATH" \
  MOCK_JUDGE_MODE="$mode" \
  ATBASH_PREHOOK_FAIL_MODE="$fail_mode" \
  ATBASH_CLI_BIN="$TMP/bin/atbash" \
  PREHOOK_PATH="$ROOT/prehook/atbash-prehook.sh" \
  MARKER="$marker" \
    bash --noprofile --norc -c \
      'source "$PREHOOK_PATH" >/dev/null; printf executed > "$MARKER"' \
      >/dev/null 2>&1 || true

  local actual=denied
  [[ -f "$marker" ]] && actual=executed

  if [[ "$actual" == "$expected" ]]; then
    printf 'ok   %-30s expected=%s\n' "$name" "$expected"
    pass=$((pass + 1))
  else
    printf 'fail %-30s expected=%s actual=%s\n' "$name" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

run_case allow                 allow     closed executed
run_case uppercase-allow       uppercase closed executed
run_case hold                  hold      closed denied
run_case block                 block     closed denied
run_case cli-error             error     closed denied
run_case timeout               timeout   closed denied
run_case empty-response        empty     closed denied
run_case malformed-response    malformed closed denied
run_case unknown-verdict       unknown   closed denied
run_case explicit-fail-open    error     allow  executed

PATH="$TMP/bin:$PATH" ATBASH_PREHOOK_ENDPOINT="http://insecure.example" \
  ATBASH_CLI_BIN="$TMP/bin/atbash" \
  PREHOOK_PATH="$ROOT/prehook/atbash-prehook.sh" \
  bash --noprofile --norc -c 'source "$PREHOOK_PATH"' >/dev/null 2>&1
endpoint_status=$?
if [[ $endpoint_status -eq 2 ]]; then
  printf 'ok   %-30s expected=install-rejected\n' "insecure-endpoint"
  pass=$((pass + 1))
else
  printf 'fail %-30s expected=install-rejected status=%s\n' "insecure-endpoint" "$endpoint_status"
  fail=$((fail + 1))
fi

mkdir -p "$TMP/empty"
PATH="$TMP/empty" PREHOOK_PATH="$ROOT/prehook/atbash-prehook.sh" \
  /usr/bin/bash --noprofile --norc -c 'source "$PREHOOK_PATH"' >/dev/null 2>&1
missing_status=$?
if [[ $missing_status -eq 2 ]]; then
  printf 'ok   %-30s expected=install-rejected\n' "missing-dependencies"
  pass=$((pass + 1))
else
  printf 'fail %-30s expected=install-rejected status=%s\n' "missing-dependencies" "$missing_status"
  fail=$((fail + 1))
fi

PATH="$TMP/bin:$PATH" ATBASH_CLI_BIN="$TMP/missing-atbash-safe" \
  PREHOOK_PATH="$ROOT/prehook/atbash-prehook.sh" \
  bash --noprofile --norc -c 'source "$PREHOOK_PATH"' >/dev/null 2>&1
launcher_status=$?
if [[ $launcher_status -eq 2 ]]; then
  printf 'ok   %-30s expected=install-rejected\n' "missing-hardened-launcher"
  pass=$((pass + 1))
else
  printf 'fail %-30s expected=install-rejected status=%s\n' "missing-hardened-launcher" "$launcher_status"
  fail=$((fail + 1))
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]

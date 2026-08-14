#!/usr/bin/env bash
# Unit tests for the sandbox DEBUG-trap prehook.
#
# The shipped prehook used to treat every non-ALLOW/HOLD/BLOCK verdict —
# including ERROR and a missing/unreachable judge — as ALLOW. These cases
# must fail closed so a down judge cannot run the intercepted command.
#
# This file is self-contained: it does not need the live Atbash CLI or Docker.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

# Working copies on Windows may be CRLF; strip CR into a temp file so bash
# can source the real prehook without process substitution.
PREHOOK_SRC="$(mktemp)"
sed 's/\r$//' "$ROOT/prehook/atbash-prehook.sh" > "$PREHOOK_SRC"
# shellcheck source=../prehook/atbash-prehook.sh
ATBASH_PREHOOK_TEST=1 source "$PREHOOK_SRC"
rm -f "$PREHOOK_SRC"

fails=0

expect_deny() {
  local verdict="$1"
  if atbash_prehook_decide "$verdict"; then
    printf '  \033[31mfail\033[0m expected deny for verdict=%s\n' "$verdict"
    fails=$((fails + 1))
  else
    printf '  \033[32mok\033[0m   denied verdict=%s\n' "$verdict"
  fi
}

expect_allow() {
  local verdict="$1"
  if atbash_prehook_decide "$verdict"; then
    printf '  \033[32mok\033[0m   allowed verdict=%s\n' "$verdict"
  else
    printf '  \033[31mfail\033[0m expected allow for verdict=%s\n' "$verdict"
    fails=$((fails + 1))
  fi
}

expect_allow ALLOW
expect_allow allow
expect_deny HOLD
expect_deny hold
expect_deny BLOCK
expect_deny block
expect_deny ERROR
expect_deny error
expect_deny ""
expect_deny UNKNOWN
expect_deny GREEN

if [[ "$fails" -eq 0 ]]; then
  printf '\033[32mPASS\033[0m prehook-fail-closed\n'
  exit 0
fi
printf '\033[31mFAIL\033[0m prehook-fail-closed (%s)\n' "$fails"
exit 1

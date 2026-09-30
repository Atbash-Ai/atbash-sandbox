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

# Arguments: the verdict word from `atbash judge --json`, the command's exit status, the JSON
# `action_type`, and the JSON `allow` ("absent" when the field is not there). Every RELEASED CLI
# prints the raw verdict word and exits 0 on a HOLD, so neither the word nor the exit status alone
# is permission: the judge's own action_type must say "allow" too, and an allow field, when
# present, must not be false. Exit codes: 0 ALLOW/LOGGED (and HOLD on released CLIs), 1 error,
# 2 BLOCK, 3 HOLD (unreleased CLIs).
describe_case() { printf 'verdict=%s action_type=%s exit=%s allow=%s' "$1" "$3" "$2" "$4"; }

expect_deny() {
  local verdict="$1" rc="${2-0}" action_type="${3-allow}" allow="${4-absent}"
  local what; what="$(describe_case "$verdict" "$rc" "$action_type" "$allow")"
  if atbash_prehook_decide "$verdict" "$rc" "$action_type" "$allow"; then
    printf '  \033[31mfail\033[0m expected deny for %s\n' "$what"
    fails=$((fails + 1))
  else
    printf '  \033[32mok\033[0m   denied %s\n' "$what"
  fi
}

expect_allow() {
  local verdict="$1" rc="${2-0}" action_type="${3-allow}" allow="${4-absent}"
  local what; what="$(describe_case "$verdict" "$rc" "$action_type" "$allow")"
  if atbash_prehook_decide "$verdict" "$rc" "$action_type" "$allow"; then
    printf '  \033[32mok\033[0m   allowed %s\n' "$what"
  else
    printf '  \033[31mfail\033[0m expected allow for %s\n' "$what"
    fails=$((fails + 1))
  fi
}

expect_allow ALLOW
expect_allow allow
expect_allow allow 0 allow true
expect_deny HOLD
expect_deny hold
expect_deny BLOCK
expect_deny block
expect_deny ERROR
expect_deny error
expect_deny ""
expect_deny UNKNOWN
expect_deny GREEN
# An "allow" the CLI itself refused (non-zero exit) is not permission.
expect_deny allow 1
expect_deny allow 2
expect_deny allow 3
expect_deny allow ""
expect_deny ALLOW 1
# A released CLI exits 0 on a HOLD and prints the raw verdict word: the judge's action_type is
# what says hold or block. An "allow" word next to it is not permission.
expect_deny allow 0 hold_for_user_confirm
expect_deny allow 0 block
expect_deny allow 0 ""
expect_deny allow 0 ALLOW-ish
expect_deny allow 0 allow false

if [[ "$fails" -eq 0 ]]; then
  printf '\033[32mPASS\033[0m prehook-fail-closed\n'
  exit 0
fi
printf '\033[31mFAIL\033[0m prehook-fail-closed (%s)\n' "$fails"
exit 1

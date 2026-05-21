#!/usr/bin/env bash
# Run the full sandbox test suite. Exits non-zero if any test fails.
#
# Usage (inside the sandbox container):
#   bash /opt/atbash/tests/run-all.sh
#
# Each sub-suite prints its own PASS/FAIL lines and returns 0 on success.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0

run_suite() {
  local name="$1"; shift
  local script="$1"; shift
  printf '\n=== %s ===\n' "$name"
  if bash "$script"; then
    printf '\033[32mPASS\033[0m %s\n' "$name"
  else
    printf '\033[31mFAIL\033[0m %s\n' "$name"
    fails=$((fails + 1))
  fi
}

run_suite "allow.sh"  "$HERE/allow.sh"
run_suite "hold.sh"   "$HERE/hold.sh"
run_suite "block.sh"  "$HERE/block.sh"
run_suite "supply-chain/atob-eval.sh"         "$HERE/supply-chain/atob-eval.sh"
run_suite "supply-chain/base64-payload.sh"    "$HERE/supply-chain/base64-payload.sh"
run_suite "supply-chain/hex-payload.sh"       "$HERE/supply-chain/hex-payload.sh"
run_suite "supply-chain/lifecycle-scripts.sh" "$HERE/supply-chain/lifecycle-scripts.sh"

printf '\n=== summary ===\n'
if [[ $fails -eq 0 ]]; then
  printf '\033[32mAll suites passed.\033[0m\n'
  exit 0
else
  printf '\033[31m%d suite(s) failed.\033[0m\n' "$fails"
  exit 1
fi

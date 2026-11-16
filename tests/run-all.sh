#!/usr/bin/env bash
# Run the full sandbox test suite. Exits non-zero if any test fails.
#
# Usage (inside the sandbox container):
#   bash /opt/atbash/tests/run-all.sh
#
# Each sub-suite prints its own PASS/FAIL lines and returns 0 on success.
#
# Suite ordering matters when the org is in Enforcement tier: a BLOCK verdict
# jails the agent and every subsequent judge call returns
# "Error: Agent is jailed." until the agent is unjailed in the dashboard.
# So block.sh runs LAST. Run with --skip-block to leave the agent unjailed
# at the end of the run (useful when iterating).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
skip_block=0

for arg in "$@"; do
  case "$arg" in
    --skip-block) skip_block=1 ;;
  esac
done

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

# Non-jailing suites first.
run_suite "allow.sh" "$HERE/allow.sh"
run_suite "hold.sh"  "$HERE/hold.sh"
run_suite "supply-chain/atob-eval.sh"         "$HERE/supply-chain/atob-eval.sh"
run_suite "supply-chain/base64-payload.sh"    "$HERE/supply-chain/base64-payload.sh"
run_suite "supply-chain/hex-payload.sh"       "$HERE/supply-chain/hex-payload.sh"
run_suite "supply-chain/lifecycle-scripts.sh" "$HERE/supply-chain/lifecycle-scripts.sh"

# block.sh runs last because in Enforcement tier the first BLOCK jails the
# agent and breaks everything after it. Skip with --skip-block when you
# want to keep using the same key for more tests right after.
if [ "$skip_block" -eq 0 ]; then
  run_suite "block.sh" "$HERE/block.sh"
  printf '\n\033[33mNote: block.sh may have jailed the agent. Unjail at https://atbash.ai/ → Settings before re-running.\033[0m\n'
else
  printf '\n(block.sh skipped — agent left unjailed)\n'
fi

printf '\n=== summary ===\n'
if [[ $fails -eq 0 ]]; then
  printf '\033[32mAll suites passed.\033[0m\n'
  exit 0
else
  printf '\033[31m%d suite(s) failed.\033[0m\n' "$fails"
  exit 1
fi

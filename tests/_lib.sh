#!/usr/bin/env bash
# Shared test helpers. Sourced by every test script.
#
# The atbash service returns verdicts as lowercase (`allow`/`hold`/`block`);
# we normalise to uppercase before comparing so tests can keep expectations
# in canonical uppercase form.

set -uo pipefail

# Internal: run `atbash judge`, return the UPPERCASED verdict on stdout.
# On error (e.g. agent jailed, network failure) surface the first line of
# stderr to the test output, and emit "EMPTY" so the caller fails loudly.
_judge() {
  local action="$1"
  local raw err
  raw=$(atbash judge "$action" --json 2>/tmp/judge.err)
  err=$(cat /tmp/judge.err 2>/dev/null)
  if [ -z "$raw" ]; then
    [ -n "$err" ] && printf '    (judge error: %s)\n' "$(echo "$err" | head -1)" >&2
    echo "EMPTY"
    return
  fi
  echo "$raw" | jq -r '.verdict // "ERROR"' | tr '[:lower:]' '[:upper:]'
}

# Expect a specific verdict.
#   expect_verdict <action> <ALLOW|HOLD|BLOCK>
expect_verdict() {
  local action="$1"
  local want="$2"
  local got
  got=$(_judge "$action")
  if [[ "$got" == "$want" ]]; then
    printf '  \033[32mok\033[0m   want=%-5s got=%-5s   %s\n' "$want" "$got" "$action"
    return 0
  else
    printf '  \033[31mfail\033[0m want=%-5s got=%-5s   %s\n' "$want" "$got" "$action"
    return 1
  fi
}

# Expect the verdict to be one of several.
#   expect_verdict_in <action> <verdict1> [verdict2 ...]
expect_verdict_in() {
  local action="$1"; shift
  local wants=("$@")
  local got
  got=$(_judge "$action")
  for w in "${wants[@]}"; do
    if [[ "$got" == "$w" ]]; then
      printf '  \033[32mok\033[0m   want=%-12s got=%-5s   %s\n' "$(IFS=/; echo "${wants[*]}")" "$got" "$action"
      return 0
    fi
  done
  printf '  \033[31mfail\033[0m want=%-12s got=%-5s   %s\n' "$(IFS=/; echo "${wants[*]}")" "$got" "$action"
  return 1
}

# Expect any valid verdict — used when the goal is "did the CLI reach the
# judge and get a usable response?" rather than asserting a specific policy
# outcome. Treats any of {ALLOW, HOLD, BLOCK} as a pass.
#   expect_any_verdict <action>
expect_any_verdict() {
  local action="$1"
  local got
  got=$(_judge "$action")
  case "$got" in
    ALLOW|HOLD|BLOCK)
      printf '  \033[32mok\033[0m   got=%-5s   %s\n' "$got" "$action"
      return 0
      ;;
    *)
      printf '  \033[31mfail\033[0m got=%-12s   %s\n' "$got" "$action"
      return 1
      ;;
  esac
}

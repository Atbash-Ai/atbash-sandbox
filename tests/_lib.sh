#!/usr/bin/env bash
# Shared test helpers. Sourced by every test script.

set -uo pipefail

# Expect a specific verdict from `atbash judge`.
#   expect_verdict <action-json> <ALLOW|HOLD|BLOCK>
expect_verdict() {
  local action="$1"
  local want="$2"
  local got
  got=$(atbash judge "$action" --json 2>/dev/null | jq -r '.verdict // "ERROR"')
  if [[ "$got" == "$want" ]]; then
    printf '  \033[32mok\033[0m   want=%-5s got=%-5s   %s\n' "$want" "$got" "$action"
    return 0
  else
    printf '  \033[31mfail\033[0m want=%-5s got=%-5s   %s\n' "$want" "$got" "$action"
    return 1
  fi
}

# Expect the verdict to be one of several (HOLD or BLOCK for risky actions).
#   expect_verdict_in <action-json> <verdict1> [verdict2 ...]
expect_verdict_in() {
  local action="$1"; shift
  local wants=("$@")
  local got
  got=$(atbash judge "$action" --json 2>/dev/null | jq -r '.verdict // "ERROR"')
  for w in "${wants[@]}"; do
    if [[ "$got" == "$w" ]]; then
      printf '  \033[32mok\033[0m   want=%-12s got=%-5s   %s\n' "$(IFS=/; echo "${wants[*]}")" "$got" "$action"
      return 0
    fi
  done
  printf '  \033[31mfail\033[0m want=%-12s got=%-5s   %s\n' "$(IFS=/; echo "${wants[*]}")" "$got" "$action"
  return 1
}

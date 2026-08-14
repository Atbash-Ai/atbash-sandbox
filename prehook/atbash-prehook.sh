#!/usr/bin/env bash
# atbash-prehook.sh
#
# Demonstrates a "prehook" pattern: every interactive shell command is sent to
# `atbash judge` BEFORE bash runs it. The verdict decides whether the command
# executes (ALLOW), is blocked (BLOCK), or is held for operator review (HOLD).
#
# This is a sandbox-only demo. There is no built-in prehook in the atbash CLI
# today; this script wires one up via bash's DEBUG trap. Enable by sourcing
# install-prehook.sh from your shell — it is OFF by default because the DEBUG
# trap fires on every command, which is noisy outside a demo context.

set -u

# Skip the trap when the prehook itself is running, or when the user is
# inspecting/disabling it, to avoid infinite recursion and lockouts.
_ATBASH_PREHOOK_GUARD=0

# Exact allowlist used by the DEBUG trap and by tests/prehook-fail-closed.sh.
# Unknown verdicts, ERROR, and an unreachable judge must not run the command.
atbash_prehook_decide() {
  case "$1" in
    allow|ALLOW) return 0 ;;
    *) return 1 ;;
  esac
}

atbash_prehook() {
  [[ $_ATBASH_PREHOOK_GUARD -eq 1 ]] && return 0
  local cmd="${BASH_COMMAND:-}"

  # Don't gate the prehook machinery itself.
  case "$cmd" in
    atbash_prehook|trap*|_ATBASH_PREHOOK_GUARD=*|"atbash judge"*|builtin*|exit*|return*) return 0 ;;
  esac

  _ATBASH_PREHOOK_GUARD=1
  local payload
  payload=$(jq -nc --arg cmd "$cmd" '{action:"shell_command",cmd:$cmd}')
  local verdict
  verdict=$(atbash judge "$payload" --json 2>/dev/null | jq -r '.verdict // "ERROR"')
  _ATBASH_PREHOOK_GUARD=0

  # API returns lowercase verdicts (allow/hold/block)
  case "$verdict" in
    allow|ALLOW)
      atbash_prehook_decide "$verdict"
      return $?
      ;;
    hold|HOLD)
      printf 'atbash prehook: \033[33mHELD\033[0m — awaiting operator review at https://atbash.ai/held\n' >&2
      printf '   command: %s\n' "$cmd" >&2
      return 1
      ;;
    block|BLOCK)
      printf 'atbash prehook: \033[31mBLOCKED\033[0m by policy\n' >&2
      printf '   command: %s\n' "$cmd" >&2
      return 1
      ;;
    *)
      printf 'atbash prehook: \033[31mBLOCKED\033[0m (judge unreachable or unusable verdict)\n' >&2
      printf '   command: %s\n' "$cmd" >&2
      atbash_prehook_decide "$verdict"
      return $?
      ;;
  esac
}

if [ "${ATBASH_PREHOOK_TEST:-}" = "1" ]; then
  return 0 2>/dev/null || true
fi

trap 'atbash_prehook' DEBUG
shopt -s extdebug
set -o functrace

echo "atbash prehook installed. Commands will be evaluated by 'atbash judge' before execution."
echo "Disable with:  trap - DEBUG"

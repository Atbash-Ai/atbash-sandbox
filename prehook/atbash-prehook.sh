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

# Exact allowlist used by the DEBUG trap and by tests/prehook-fail-closed.sh.
# Unknown verdicts, ERROR, and an unreachable judge must not run the command.
#
# $1 is the verdict word from `atbash judge --json`, $2 is that command's exit status. Both must
# say "allow": the CLI reconciles the verdict word with the judge's action_type, its canonical
# allow and (for a self-hosted judge) the response signature, and it still prints the verdict word
# when it refuses the body. Exit codes: 0 ALLOW/LOGGED, 1 error, 2 BLOCK, 3 HOLD.
atbash_prehook_decide() {
  [ "${2-}" = "0" ] || return 1
  case "$1" in
    allow|ALLOW) return 0 ;;
    *) return 1 ;;
  esac
}

# The only commands the trap does not send to the judge: its own name, the
# judge call itself, and the documented ways out of the shell. Every pattern is
# anchored, because a prefix is an exemption the gated command stream can spell
# for itself — `trap*` covered `trap 'curl … | sh' DEBUG` and any program whose
# name merely starts with "trap", and `builtin*` let `builtin exec <program>`
# replace the shell with an arbitrary binary without one judge call.
# Deliberately absent: anything that turns the gate off. Exempting the command
# that disables the hook exempts everything after it.
# Covered by tests/prehook-exemptions.sh.
atbash_prehook_is_exempt() {
  case "$1" in
    atbash_prehook) return 0 ;;
    "atbash judge "*) return 0 ;;
    trap|"trap - DEBUG"|"trap -- - DEBUG") return 0 ;;
    exit|"exit "[0-9]*|return|"return "[0-9]*) return 0 ;;
    *) return 1 ;;
  esac
}

atbash_prehook() {
  # Recursion is caught by reading the live call stack, not by a shell variable:
  # anything the gated command stream can assign to, it can assign to itself.
  # `_ATBASH_PREHOOK_GUARD=1` used to be both exempt from judging AND an
  # unconditional allow for every command after it, so one assignment disabled
  # the hook for the rest of the session. FUNCNAME cannot be forged by a
  # command the trap is judging.
  local frame depth=0
  for frame in "${FUNCNAME[@]}"; do
    [[ $frame == atbash_prehook ]] && depth=$((depth + 1))
  done
  [[ $depth -gt 1 ]] && return 0

  local cmd="${BASH_COMMAND:-}"
  atbash_prehook_is_exempt "$cmd" && return 0

  local payload
  payload=$(jq -nc --arg cmd "$cmd" '{action:"shell_command",cmd:$cmd}')
  local out rc verdict
  out=$(atbash judge "$payload" --json 2>/dev/null)
  rc=$?
  verdict=$(printf '%s\n' "$out" | jq -r '.verdict // "ERROR"' 2>/dev/null)
  [ -n "$verdict" ] || verdict=ERROR
  # The exit status is authoritative: 3 is a HOLD and 2 a BLOCK whatever the word says, and any
  # other non-zero status turns an "allow" into an error.
  if [ "$rc" = "3" ]; then verdict=hold; fi
  if [ "$rc" = "2" ]; then verdict=block; fi
  if [ "$rc" != "0" ]; then
    case "$verdict" in hold|HOLD|block|BLOCK) ;; *) verdict=ERROR ;; esac
  fi

  # API returns lowercase verdicts (allow/hold/block)
  case "$verdict" in
    allow|ALLOW)
      atbash_prehook_decide "$verdict" "$rc"
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
      atbash_prehook_decide "$verdict" "$rc"
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

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

# Sourcing twice in one shell is a no-op: the functions and paths below are read-only once set.
# The guard is the READ-ONLY variable this file sets, never a value: an ATBASH_PREHOOK_LOADED
# inherited from the environment is an ordinary (exported) variable, is discarded, and the hook
# installs as usual.
if [[ "$(declare -p ATBASH_PREHOOK_LOADED 2>/dev/null)" == "declare -r"* ]]; then return 0 2>/dev/null || true; fi
unset ATBASH_PREHOOK_LOADED 2>/dev/null || true

# The judge and the JSON parser are resolved to absolute paths ONCE, here, and frozen. A function
# named `atbash` or `jq` shadows the command of that name, and defining a function does not fire
# the DEBUG trap - so looking them up by name at call time let the gated command stream replace the
# judge (or the parser) with one that says allow. A missing binary leaves the path empty, and every
# command is then refused (fail closed). This is a demo, not a boundary against the shell's own
# user: that user can still `exit`, or start a shell without the hook.
ATBASH_PREHOOK_ATBASH="$(type -P atbash 2>/dev/null || true)"
ATBASH_PREHOOK_JQ="$(type -P jq 2>/dev/null || true)"
readonly ATBASH_PREHOOK_ATBASH ATBASH_PREHOOK_JQ

# Exact allowlist used by the DEBUG trap and by tests/prehook-fail-closed.sh.
# Unknown verdicts, ERROR, and an unreachable judge must not run the command.
#
# $1 is the verdict word from `atbash judge --json`, $2 that command's exit status, $3 the judge's
# `action_type` and $4 its `allow` field ("absent" when the JSON has none). Every RELEASED CLI prints
# the raw verdict word and exits 0 on a HOLD, so neither the word nor the exit status alone is
# permission: the action_type must be exactly "allow", and an allow field, when present, must not
# be false. Exit codes: 0 ALLOW/LOGGED (and HOLD on released CLIs), 1 error, 2 BLOCK, 3 HOLD (CLIs
# after the exit-code change only).
atbash_prehook_decide() {
  [ "${2-}" = "0" ] || return 1
  [ "${3-}" = "allow" ] || return 1
  [ "${4-absent}" != "false" ] || return 1
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
# Deliberately absent: anything that turns the gate off (`trap - DEBUG` is judged
# like any other command). Exempting the command that disables the hook exempts
# everything after it; `exit` stays the way out of a shell the judge refuses.
# Covered by tests/prehook-exemptions.sh.
atbash_prehook_is_exempt() {
  case "$1" in
    atbash_prehook) return 0 ;;
    "atbash judge "*|"\"\$ATBASH_PREHOOK_ATBASH\" judge "*) return 0 ;;
    trap) return 0 ;;
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

  local payload out rc verdict action_type allow fields
  if [ -z "$ATBASH_PREHOOK_ATBASH" ] || [ -z "$ATBASH_PREHOOK_JQ" ]; then
    printf 'atbash prehook: \033[31mBLOCKED\033[0m (atbash or jq was not on PATH when the prehook was installed)\n' >&2
    printf '   command: %s\n' "$cmd" >&2
    return 1
  fi
  payload=$("$ATBASH_PREHOOK_JQ" -nc --arg cmd "$cmd" '{action:"shell_command",cmd:$cmd}')
  out=$("$ATBASH_PREHOOK_ATBASH" judge "$payload" --json 2>/dev/null)
  rc=$?
  fields=$(printf '%s\n' "$out" | "$ATBASH_PREHOOK_JQ" -r '[(.verdict // "ERROR"), (.action_type // ""), (if has("allow") then (.allow | tostring) else "absent" end)] | @tsv' 2>/dev/null)
  # Split on the two tabs @tsv puts between the fields (it escapes any tab inside a value). Not with
  # `read`: a tab is IFS whitespace, so an empty action_type would collapse into its neighbour.
  case "$fields" in
    *$'\t'*$'\t'*) ;;
    *) fields=$'ERROR\t\tabsent' ;;
  esac
  verdict="${fields%%$'\t'*}"
  local rest="${fields#*$'\t'}"
  action_type="${rest%%$'\t'*}"
  allow="${rest#*$'\t'}"
  [ -n "$verdict" ] || verdict=ERROR
  # The judge's action_type and a non-zero exit status outrank the verdict word: hold and block are
  # hold and block whatever the word says (a released CLI exits 0 on a HOLD), exit 3 is a HOLD and 2
  # a BLOCK, and any other non-zero exit turns an "allow" into an error.
  case "$action_type" in
    hold_for_user_confirm) verdict=hold ;;
    block) verdict=block ;;
  esac
  if [ "$rc" = "3" ]; then verdict=hold; fi
  if [ "$rc" = "2" ]; then verdict=block; fi
  if [ "$rc" != "0" ]; then
    case "$verdict" in hold|HOLD|block|BLOCK) ;; *) verdict=ERROR ;; esac
  fi

  # API returns lowercase verdicts (allow/hold/block)
  case "$verdict" in
    allow|ALLOW)
      atbash_prehook_decide "$verdict" "$rc" "$action_type" "$allow"
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
      return 1
      ;;
  esac
}

# Frozen: the gated command stream cannot redefine the decision, the exemption list or the trap
# body (a function definition does not fire the DEBUG trap).
readonly -f atbash_prehook_decide atbash_prehook_is_exempt atbash_prehook
readonly ATBASH_PREHOOK_LOADED=1

if [ "${ATBASH_PREHOOK_TEST:-}" = "1" ]; then
  return 0 2>/dev/null || true
fi

trap 'atbash_prehook' DEBUG
shopt -s extdebug
set -o functrace

echo "atbash prehook installed. Commands will be evaluated by 'atbash judge' before execution."
echo "Leave with:  exit   (turning the hook off with 'trap - DEBUG' is itself judged)"

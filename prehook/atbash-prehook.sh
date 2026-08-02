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

# This file must be sourced because it installs a trap in the current shell.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  printf 'atbash-prehook.sh must be sourced, not executed\n' >&2
  exit 2
fi

# Resolve required tools before installing the trap. Using absolute paths
# prevents a later PATH change or shadow binary from replacing the evaluator.
_ATBASH_PREHOOK_JQ="$(type -P jq 2>/dev/null || true)"
_ATBASH_PREHOOK_TIMEOUT="$(type -P timeout 2>/dev/null || true)"
_ATBASH_PREHOOK_ENV="$(type -P env 2>/dev/null || true)"
_ATBASH_PREHOOK_CLI="${ATBASH_CLI_BIN:-/usr/local/bin/atbash-safe}"

if [[ -z "$_ATBASH_PREHOOK_JQ" || -z "$_ATBASH_PREHOOK_TIMEOUT" || -z "$_ATBASH_PREHOOK_ENV" || -z "$_ATBASH_PREHOOK_CLI" ]]; then
  printf 'atbash prehook: jq, timeout, env, and atbash must be installed before enabling the hook\n' >&2
  return 2
fi
if [[ ! -x "$_ATBASH_PREHOOK_CLI" ]]; then
  printf 'atbash prehook: hardened CLI launcher is not executable: %s\n' \
    "$_ATBASH_PREHOOK_CLI" >&2
  return 2
fi

# Skip the trap when the prehook itself is running, or when the user is
# inspecting/disabling it, to avoid infinite recursion and lockouts.
_ATBASH_PREHOOK_GUARD=0

# Availability policy. Security defaults to fail-closed: only an explicit,
# valid ALLOW verdict permits execution. Set ATBASH_PREHOOK_FAIL_MODE=allow
# only for a non-enforcing demo shell where availability matters more than
# enforcement. Judge calls are bounded so a network outage cannot hang bash.
ATBASH_PREHOOK_FAIL_MODE="${ATBASH_PREHOOK_FAIL_MODE:-closed}"
ATBASH_PREHOOK_TIMEOUT_SECONDS="${ATBASH_PREHOOK_TIMEOUT_SECONDS:-5}"
ATBASH_PREHOOK_ENDPOINT="${ATBASH_PREHOOK_ENDPOINT:-https://atbash.ai}"

case "$ATBASH_PREHOOK_FAIL_MODE" in
  closed|allow) ;;
  *)
    printf 'atbash prehook: invalid ATBASH_PREHOOK_FAIL_MODE=%q (use closed or allow)\n' \
      "$ATBASH_PREHOOK_FAIL_MODE" >&2
    return 2
    ;;
esac

case "$ATBASH_PREHOOK_TIMEOUT_SECONDS" in
  ''|*[!0-9]*)
    printf 'atbash prehook: ATBASH_PREHOOK_TIMEOUT_SECONDS must be a positive integer\n' >&2
    return 2
    ;;
  0)
    printf 'atbash prehook: ATBASH_PREHOOK_TIMEOUT_SECONDS must be greater than zero\n' >&2
    return 2
    ;;
esac

case "$ATBASH_PREHOOK_ENDPOINT" in
  https://*) ;;
  *)
    printf 'atbash prehook: ATBASH_PREHOOK_ENDPOINT must use https://\n' >&2
    return 2
    ;;
esac

_atbash_prehook_unavailable() {
  local cmd="$1"

  if [[ "$ATBASH_PREHOOK_FAIL_MODE" == "allow" ]]; then
    printf 'atbash prehook: \033[33mjudge unavailable — ALLOWING because fail mode is allow\033[0m\n' >&2
    printf '   command: %s\n' "$cmd" >&2
    return 0
  fi

  printf 'atbash prehook: \033[31mDENIED\033[0m — no valid judge verdict\n' >&2
  printf '   command: %s\n' "$cmd" >&2
  return 1
}

atbash_prehook() {
  [[ $_ATBASH_PREHOOK_GUARD -eq 1 ]] && return 0
  local cmd="${BASH_COMMAND:-}"

  # Don't gate the prehook machinery itself.
  case "$cmd" in
    atbash_prehook|trap*|_ATBASH_PREHOOK_GUARD=*|"atbash judge"*|builtin*|exit*|return*) return 0 ;;
  esac

  _ATBASH_PREHOOK_GUARD=1
  local payload response verdict judge_status parse_status
  # shellcheck disable=SC2016 # jq program; $cmd is populated by --arg.
  payload=$("$_ATBASH_PREHOOK_JQ" -nc --arg cmd "$cmd" '{action:"shell_command",cmd:$cmd}' 2>/dev/null)
  parse_status=$?
  if [[ $parse_status -ne 0 || -z "$payload" ]]; then
    _ATBASH_PREHOOK_GUARD=0
    _atbash_prehook_unavailable "$cmd"
    return $?
  fi

  response=$("$_ATBASH_PREHOOK_TIMEOUT" "${ATBASH_PREHOOK_TIMEOUT_SECONDS}s" \
    "$_ATBASH_PREHOOK_ENV" -u ATBASH_ENDPOINT \
    "$_ATBASH_PREHOOK_CLI" judge "$payload" --endpoint "$ATBASH_PREHOOK_ENDPOINT" --json 2>/dev/null)
  judge_status=$?
  if [[ $judge_status -eq 0 && -n "$response" ]]; then
    verdict=$(printf '%s' "$response" | "$_ATBASH_PREHOOK_JQ" -er \
      '.verdict | strings | ascii_downcase | select(. == "allow" or . == "hold" or . == "block")' \
      2>/dev/null)
    parse_status=$?
  else
    verdict=""
    parse_status=1
  fi
  _ATBASH_PREHOOK_GUARD=0

  if [[ $judge_status -ne 0 || $parse_status -ne 0 || -z "$verdict" ]]; then
    _atbash_prehook_unavailable "$cmd"
    return $?
  fi

  case "$verdict" in
    allow)
      return 0
      ;;
    hold)
      printf 'atbash prehook: \033[33mHELD\033[0m — awaiting operator review at https://atbash.ai/held\n' >&2
      printf '   command: %s\n' "$cmd" >&2
      return 1
      ;;
    block)
      printf 'atbash prehook: \033[31mBLOCKED\033[0m by policy\n' >&2
      printf '   command: %s\n' "$cmd" >&2
      return 1
      ;;
    *)
      # Defensive fallback. The strict jq expression above should make this
      # branch unreachable, but an unknown verdict must never become ALLOW.
      _atbash_prehook_unavailable "$cmd"
      return $?
      ;;
  esac
}

trap 'atbash_prehook' DEBUG
shopt -s extdebug
set -o functrace

echo "atbash prehook installed. Commands will be evaluated by 'atbash judge' before execution."
echo "Disable with:  trap - DEBUG"

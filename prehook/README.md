# Prehook (opt-in)

A *prehook* gates every shell command through `atbash judge` **before** bash
runs it. The command runs only on an explicit `ALLOW`. `BLOCK`, `HOLD`,
`ERROR`, and an unreachable judge all refuse the command.

"Explicit" means every part of the CLI's `--json` answer agrees: the verdict
word is `allow`, the judge's `action_type` is exactly `allow`, an `allow` field
(when present) is not `false`, **and** `atbash judge` exited `0`.

Why all of them: every **released** `@atbash/cli` (the image pins
`ATBASH_CLI_VERSION`, see the `Dockerfile`) prints the judge's raw verdict word
and exits `0` on a HOLD, so `{"verdict":"allow","action_type":"hold_for_user_confirm"}`
is a hold, not an allow. The CLI also prints the word when it refuses the
response (exit `1`). Released exit codes: `0` ALLOW, LOGGED **and HOLD**, `1`
error, `2` BLOCK. A pending CLI change makes HOLD exit `3`; until that CLI is
released and pinned here, **do not gate a command with
`atbash judge '...' && <command>`** - on a released CLI that runs held actions.
Read `action_type` from `--json` instead, as the prehook does.

This is **a sandbox-only demonstration** of the pattern — there is no built-in
prehook in the atbash CLI today. Inside this container the wiring is a bash
`DEBUG` trap; in a production agent it would be a wrapper around the agent's
tool-call layer.

**It is not a security boundary against the shell's own user.** It makes the
judge the default for every command, and it resists the easy ways around it:
`atbash` and `jq` are resolved to absolute paths when the prehook is installed
(a shell function with either name cannot replace the judge or the parser), the
prehook's functions are read-only (they cannot be redefined), and turning the
trap off is judged like any other command. But the user can still `exit`, or
start a shell that never sources the hook. A real boundary sits at the agent's
tool-call layer, outside the process it gates.

## Why it is off by default

The `DEBUG` trap fires on every command, including `cd`, `ls`, and the
prehook's own internal calls. Outside a demo that is too noisy and adds
real latency. The point of shipping it disabled is to make turning it on a
deliberate decision.

## What is never sent to the judge

Four things, matched exactly — not by prefix:

| Exempt | Why |
|---|---|
| `atbash_prehook` | the trap's own function; judging it would recurse |
| `atbash judge …` | the judge call the trap itself makes |
| `trap` | prints the traps; changes nothing |
| `exit`, `exit N`, `return`, `return N` | the way out of the shell, so the hook cannot lock you out |

`trap - DEBUG` (turning the hook off) is **not** exempt: it goes to the judge
like any other command. `exit` is the way out.

Everything else is judged, including anything that would disable the hook.
Exact matching is the point: `trap*` used to exempt `trap 'curl … \| sh' DEBUG`
and any program whose name merely starts with "trap", `builtin*` let
`builtin exec <program>` replace the shell with any binary, and the recursion
guard variable was itself exempt — so a single `_ATBASH_PREHOOK_GUARD=1` turned
the gate off for the whole session. The guard is gone; recursion is now detected
from the call stack, which a judged command cannot forge.

`tests/prehook-exemptions.sh` runs the real trap against a stub judge that
denies everything and asserts that each of those commands still reaches it.

## Enable for the current shell

```bash
source /opt/atbash/prehook/install-prehook.sh
```

You will see `atbash prehook installed.` confirming the trap is in place.

## Make it permanent inside the sandbox container

```bash
echo 'source /opt/atbash/prehook/install-prehook.sh' >> ~/.bashrc
```

## Disable

Exit the shell. `trap - DEBUG` also works when the judge allows it - turning the
gate off is itself a judged command.

## What you should see

```bash
$ atbash judge '{"action":"read_file","path":"./README.md"}' --json
{"verdict":"ALLOW",...}              # plain CLI call — always works

$ ls                                  # prehook intercepts, judge returns ALLOW
README.md  ...

$ rm -rf /                            # prehook intercepts, judge returns BLOCK
atbash prehook: BLOCKED by policy
   command: rm -rf /
```

## Cleanup

```bash
trap - DEBUG
shopt -u extdebug
set +o functrace
```

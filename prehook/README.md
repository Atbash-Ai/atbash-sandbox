# Prehook (opt-in)

A *prehook* gates every shell command through `atbash judge` **before** bash
runs it. The command runs only on an explicit `ALLOW`. `BLOCK`, `HOLD`,
`ERROR`, and an unreachable judge all refuse the command.

This is **a sandbox-only demonstration** of the pattern — there is no built-in
prehook in the atbash CLI today. Inside this container the wiring is a bash
`DEBUG` trap; in a production agent it would be a wrapper around the agent's
tool-call layer.

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
| `trap`, `trap - DEBUG` | the documented off switch, so the hook cannot lock you out |
| `exit`, `exit N`, `return`, `return N` | the way out of the shell |

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

```bash
trap - DEBUG
```

Or simply exit the shell.

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

# Prehook (opt-in)

A *prehook* gates every shell command through `atbash judge` **before** bash
runs it. If the verdict is `BLOCK` or `HOLD`, the command never executes.

This is **a sandbox-only demonstration** of the pattern — there is no built-in
prehook in the atbash CLI today. Inside this container the wiring is a bash
`DEBUG` trap; in a production agent it would be a wrapper around the agent's
tool-call layer.

## Why it is off by default

The `DEBUG` trap fires on every command, including `cd`, `ls`, and the
prehook's own internal calls. Outside a demo that is too noisy and adds
real latency. The point of shipping it disabled is to make turning it on a
deliberate decision.

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

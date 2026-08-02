# Prehook (opt-in)

A *prehook* gates every shell command through `atbash judge` **before** bash
runs it. If the verdict is `BLOCK` or `HOLD`, the command never executes.
Only an explicit, valid `ALLOW` verdict executes a command. A timeout, CLI
error, missing dependency, empty response, malformed JSON, or unknown verdict
is denied by default.

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

The judge call has a five-second default timeout. You can select a different
positive whole number before enabling the hook:

```bash
export ATBASH_PREHOOK_TIMEOUT_SECONDS=3
source /opt/atbash/prehook/install-prehook.sh
```

The prehook pins its judge destination independently of general CLI
configuration. It defaults to `https://atbash.ai`; an authorized alternate
HTTPS endpoint must be selected explicitly with `ATBASH_PREHOOK_ENDPOINT`
before installation. Plain HTTP is rejected.

## Failure behavior

The default is **fail closed**:

```text
ALLOW                          command executes
HOLD or BLOCK                  command is denied
timeout/error/malformed reply  command is denied
```

For a non-enforcing demonstration only, fail-open behavior can be requested
explicitly before sourcing the hook:

```bash
export ATBASH_PREHOOK_FAIL_MODE=allow
source /opt/atbash/prehook/install-prehook.sh
```

This setting is unsafe for enforcement and prints a prominent warning whenever
it permits a command without a verdict.

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

## Security boundary and availability

A bash `DEBUG` trap is an advisory demonstration, not a boundary against a
hostile shell user. The user can remove the trap or start another shell, and
the hook sees a command such as `python script.py` rather than every operation
performed inside that program. Production enforcement belongs outside the
controlled process, at the agent tool-call or execution-broker boundary.

It is not possible to guarantee that a remote judge is never down. Redundant
instances, health checks, retries, and multiple regions reduce downtime but do
not eliminate partitions. Safe operation therefore needs both:

1. a bounded remote call that fails closed; and
2. for offline operation, a locally verifiable, signed policy bundle evaluated
   by the same deterministic policy engine as the service.

A hand-written emergency allowlist or cached ALLOW result is not equivalent to
the current policy and can authorize stale or context-dependent actions. Until
the CLI supports signed local policy evaluation, this demo denies commands
when it cannot obtain a live verdict. See
[`../docs/prehook-availability.md`](../docs/prehook-availability.md).

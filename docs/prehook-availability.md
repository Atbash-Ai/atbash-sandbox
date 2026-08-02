# Prehook availability and offline decisions

## Decision

The shell prehook is **fail closed by default**. A command executes only after
the hook receives and validates an explicit `ALLOW` verdict. Network failure,
timeout, CLI failure, empty output, malformed JSON, and unknown verdicts deny
the command.

This chooses safety over availability. A remote dependency cannot be made
literally "never down": processes crash, credentials expire, networks
partition, DNS fails, and regions can become unavailable. High availability
reduces failures; deterministic local evaluation provides a controlled way to
operate through them.

## Current behavior

The hook applies a bounded timeout to every judge call:

```text
valid ALLOW                    execute
valid HOLD or BLOCK            deny
judge timeout or non-zero exit deny
empty or malformed response    deny
unknown verdict                deny
```

The timeout defaults to five seconds and can be configured before installation:

```bash
export ATBASH_PREHOOK_TIMEOUT_SECONDS=3
source /opt/atbash/prehook/install-prehook.sh
```

A fail-open demonstration mode exists for interactive product demos where loss
of shell availability is more costly than enforcement:

```bash
export ATBASH_PREHOOK_FAIL_MODE=allow
source /opt/atbash/prehook/install-prehook.sh
```

It must not be used or described as enforcement.

## Target design for deterministic offline judging

Offline judging should not be a separate set of ad hoc regular expressions.
The service and local evaluator must consume the same canonical policy model
and produce the same result for the same complete input.

A policy bundle should contain at least:

- policy rules and evaluation-engine version;
- organization and agent scope;
- bundle version and issued-at timestamp;
- expiry timestamp and maximum offline lifetime;
- monotonically increasing policy revision;
- revocation epoch or equivalent rollback protection;
- cryptographic hash of canonical bundle contents; and
- signature from an Atbash policy-signing key whose public key is pinned in the
  client.

Before using a bundle, the client must verify:

1. signature and canonical content hash;
2. organization and agent scope;
3. supported evaluator version;
4. expiry and maximum offline age;
5. policy revision is not older than the highest accepted revision; and
6. all context required by the policy is available locally.

If a rule needs remote state—operator approval, jail status, risk-engine state,
revocation state, counters, or mutable organization context—the local evaluator
must return `HOLD` or `BLOCK`, never guess `ALLOW`.

Offline decisions should be recorded in an append-only local queue containing
the policy revision, normalized input hash, verdict, reason, timestamp, and a
per-installation sequence number. The queue is uploaded and reconciled when
connectivity returns. Do not cache an `ALLOW` verdict solely by command string:
policy, identity, time, working directory, arguments, and external state may
have changed.

## Online availability controls

The service path should still use standard high-availability controls:

- multiple instances behind health-checked load balancing;
- at least two failure domains, and multiple regions if the threat model needs
  regional continuity;
- short client timeout with a tightly bounded retry budget;
- retries only for safe/idempotent judge requests, using a request ID to avoid
  duplicate audit records;
- circuit breaking and readiness checks;
- monitored latency, error-rate, and policy-freshness service-level objectives;
- tested regional failover and disaster recovery; and
- separate policy-distribution and decision-service monitoring.

These controls reduce outage frequency but do not replace fail-closed or signed
local evaluation.

## Threat-model limitation

The repository prehook uses a Bash `DEBUG` trap. A user who controls the shell
can remove or replace the trap, start another shell, or launch a program whose
internal operations are not visible to the hook. Signed offline policies solve
judge availability; they do not turn a shell trap into a tamper-resistant
boundary.

Production enforcement should call the online/local evaluator from an agent
execution broker or tool-call boundary that the controlled process cannot
modify or bypass.

## Implementation phases

### Phase 1 — implemented in this repository

- fail closed by default;
- bounded judge timeout;
- strict verdict parsing;
- explicit warning-only fail-open demo mode; and
- unit tests for allow, hold, block, timeout, CLI error, malformed output, and
  unknown verdict.

### Phase 2 — CLI/SDK work

- define canonical judge input and policy bundle schemas;
- implement signed bundle download and verification;
- embed the same deterministic evaluator used by the service;
- protect against expired, revoked, and rolled-back bundles;
- implement offline audit queue and reconciliation; and
- publish cross-evaluator parity vectors.

### Phase 3 — production boundary

- move enforcement from Bash into a non-bypassable execution broker;
- deploy and exercise multi-failure-domain judge service;
- define availability and policy-freshness SLOs; and
- run outage, stale-policy, key-rotation, and revocation drills.

## Acceptance criteria

Offline mode is suitable for enforcement only when:

- online and local evaluators pass identical signed test vectors;
- an invalid, expired, wrong-scope, unsupported, or rolled-back bundle cannot
  produce `ALLOW`;
- policies requiring unavailable remote state cannot produce offline `ALLOW`;
- every offline decision is attributable to a verified policy revision; and
- bypassing the evaluator requires crossing an operating-system or service
  authorization boundary, not merely changing shell state.

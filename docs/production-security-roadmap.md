# Production security roadmap

The repository hardening in this pull request closes the locally reproducible
container, supply-chain, secret-handling, and judge-invocation findings. The
following controls require service or deployment architecture and therefore
cannot be honestly represented as completed by a portable sandbox template.

## 1. Controlled egress

The tested container can reach arbitrary public HTTPS destinations. Production
deployments must route runtime traffic through an authenticated egress proxy or
provider firewall and permit only approved Atbash endpoints. Explicitly deny
link-local and cloud metadata ranges, including `169.254.169.254`.

Acceptance tests:

- approved judge endpoint succeeds;
- an arbitrary public endpoint fails;
- metadata and link-local destinations fail; and
- DNS rebinding and direct-IP attempts do not bypass the policy.

## 2. Non-bypassable enforcement broker

The Bash DEBUG trap is an advisory demonstration. A process that controls the
shell can remove the trap or start another shell. Production agents must submit
structured tool calls to a separate execution broker that owns the credentials
and operating-system permissions needed to perform the action. The agent must
not have a second path to the protected resource.

Acceptance tests:

- bypassing the broker cannot reach protected APIs, files, or sockets;
- judge failure and malformed replies fail closed;
- broker decisions and executions share a request ID and audit record; and
- agent-controlled environment variables cannot replace the evaluator.

## 3. Signed deterministic offline policy

Offline operation requires a signed policy bundle evaluated by the same
deterministic engine as the service. See `prehook-availability.md`. Until that
exists, unavailable remote judging must deny rather than use a handwritten
allowlist or cached ALLOW.

## 4. Platform validation

Each advertised platform needs a recorded build, deployment, runtime security,
network, secret-rotation, and teardown test. Cloud Run must be redesigned as a
Job or a real authenticated service that listens on `$PORT`; the current
shell-only image is not a valid Cloud Run Service workload.

# Security policy

## Reporting a vulnerability

Do not open a public issue for an unpatched vulnerability, leaked credential,
or bypass technique. Use GitHub's private vulnerability reporting feature for
this repository. If that feature is unavailable, contact the repository owners
through a private organization channel and ask for a security contact before
sharing technical details.

Include the affected commit/version, reproduction steps, impact, prerequisites,
and any suggested mitigation. Do not access data that is not yours, disrupt the
hosted Atbash service, or test third-party cloud deployments without explicit
authorization.

## Supported versions

Security fixes are applied to the default branch. This sandbox is a reference
implementation rather than a long-term-supported runtime release; deploy from
a reviewed commit and immutable image digest.

## Scope boundary

The Bash prehook is an advisory demonstration and is not a tamper-resistant
boundary against a user who controls the shell. Reports about an unexpected
fail-open path, credential disclosure, container escape, dependency compromise,
or bypass of a separately deployed execution broker are in scope.

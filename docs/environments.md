# Environment and promotion contract

The sandbox image contains the same CLI artifact in every environment. The
endpoint, organization, agent key, image identity, and promotion authority must
remain environment-specific.

| Environment | Purpose | Credentials and endpoint | Artifact rule |
|---|---|---|---|
| Development | Local iteration with Docker Compose | Disposable development agent and a non-production endpoint | Build locally from the reviewed Dockerfile |
| Testing | CI and integration verification | Dedicated testing agent/org; never a production key | Record the image digest that passed static, container, and live integration checks |
| Production | Explicitly approved runtime | Production secret store and production endpoint only | Promote the exact tested digest; do not rebuild or resolve `latest` |

Promotion is one-way: development to testing to production. A production
promotion requires the same pinned CLI version and image digest that passed the
testing gate, an approved change, and a rollback digest. Never copy `.env`, an
agent private key, or a mutable testing image tag between environments.

The current Cloud Build and service examples still publish and reference the
mutable image tag `latest`. Treat those files as development examples until the
deployment pipeline substitutes or resolves an immutable digest. Render and
Fly deployments likewise need their platform release record to capture the
tested image digest before production use.

# Google Cloud Run

Cloud Run has no one-click button, but the deploy is two `gcloud` commands.
The service is **internal-only** by default (`ingress: internal`) — no public
URL is created.

## Prerequisites

- `gcloud` CLI, authenticated against a project with billing enabled.
- Cloud Run, Cloud Build, and Secret Manager APIs enabled:
  ```bash
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com secretmanager.googleapis.com
  ```

## Deploy in ~5 minutes

```bash
PROJECT_ID=your-gcp-project
REGION=us-central1

# 1. Create the service account.
gcloud iam service-accounts create atbash-sandbox-sa --display-name="Atbash sandbox"

# 2. Store secrets.
printf '%s' "$ATBASH_AGENT_KEY" | gcloud secrets create atbash-agent-key --data-file=-
printf '%s' "$ATBASH_ORG_NAME"  | gcloud secrets create atbash-org-name  --data-file=-

# 3. Grant the SA access to the secrets.
for s in atbash-agent-key atbash-org-name; do
  gcloud secrets add-iam-policy-binding "$s" \
    --member="serviceAccount:atbash-sandbox-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role=roles/secretmanager.secretAccessor
done

# 4. Build the image.
gcloud builds submit --config cloud-run/cloudbuild.yaml --substitutions=_VERSION=latest .

# 5. Replace PROJECT_ID in the service spec and deploy.
sed "s/PROJECT_ID/${PROJECT_ID}/" cloud-run/service.yaml | \
  gcloud run services replace - --region="$REGION"

# 6. Connect.
gcloud run services proxy atbash-sandbox --region="$REGION"
# In another terminal, the local URL is http://localhost:8080 — but the
# sandbox is shell-only, so for interactive use:
gcloud run services execute atbash-sandbox --region="$REGION" --command="bash -i"
```

## Security posture on Cloud Run

| Requirement              | How it's enforced on Cloud Run                                           |
|--------------------------|---------------------------------------------------------------------------|
| Non-root user            | `securityContext.runAsNonRoot: true`, `runAsUser: 10001`.                 |
| Config permissions 600   | Set at image build time.                                                  |
| No host mounts           | Cloud Run does not allow host filesystem mounts.                          |
| No local secrets         | Secret Manager + `secretKeyRef`. `service.yaml` references names only.    |
| Read-only root FS        | `securityContext.readOnlyRootFilesystem: true`.                           |
| Drop capabilities        | `capabilities.drop: [ALL]`.                                               |
| No privilege escalation  | `allowPrivilegeEscalation: false`.                                        |
| Internal ingress only    | `run.googleapis.com/ingress: internal` — no public URL.                   |
| Pinned CLI version       | Image tag is `:latest`; bump explicitly.                                  |

## Teardown

```bash
gcloud run services delete atbash-sandbox --region="$REGION"
gcloud secrets delete atbash-agent-key
gcloud secrets delete atbash-org-name
gcloud iam service-accounts delete atbash-sandbox-sa@${PROJECT_ID}.iam.gserviceaccount.com
```

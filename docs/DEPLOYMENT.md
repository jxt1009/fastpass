# Deployment Guide

This repository deploys the backend through GitHub Actions using a staged promotion model.

---

## Deployment model

Workflow: [`.github/workflows/backend-deploy.yml`](../.github/workflows/backend-deploy.yml)

On pushes to `main` that touch backend deploy paths:

1. Build and push backend image to GHCR.
2. Deploy to **staging** (`fasttrack-staging`).
3. Deploy to **production** (`fasttrack-production`) after `production` environment approval.

## Namespaces and environments

| GitHub Environment | Kubernetes Namespace | Promotion |
|---|---|---|
| `staging` | `fasttrack-staging` | automatic |
| `production` | `fasttrack-production` | manual approval |

---

## Required secrets

Set these as environment secrets in both `staging` and `production` unless noted:

- `KUBECONFIG` (base64-encoded)
- `JWT_SECRET`
- `APPLE_APP_BUNDLE_ID`
- `GOOGLE_CLIENT_ID` (optional if not using Google auth)
- `GOOGLE_CLIENT_SECRET` (optional if not using Google auth)
- `STAGING_DATABASE_URL` (`staging` only)
- `PRODUCTION_DATABASE_URL` (`production` only)
- `STAGING_BASE_URL` (`staging` only)
- `PRODUCTION_BASE_URL` (`production` only)

---

## Kubernetes overlays

Backend manifests are organized under:

- `backend/k8s/base`
- `backend/k8s/overlays/staging`
- `backend/k8s/overlays/production`

Each deploy job updates the image tag, applies the environment overlay, and waits for rollout completion.

---

## Operational commands

```bash
# Staging
kubectl get all -n fasttrack-staging
kubectl rollout status deployment/fasttrack-api -n fasttrack-staging

# Production
kubectl get all -n fasttrack-production
kubectl rollout status deployment/fasttrack-api -n fasttrack-production

# Logs
kubectl logs -f deployment/fasttrack-api -n fasttrack-staging
kubectl logs -f deployment/fasttrack-api -n fasttrack-production
```

---

## Manual/local deploy helpers

Manual helper scripts remain available in [`scripts/`](../scripts/README.md) for local or ad hoc workflows, but the production path is GitHub Actions.

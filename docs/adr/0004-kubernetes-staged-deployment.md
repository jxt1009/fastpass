# ADR-0004: Staged Kubernetes Deployment (Staging → Production)

**Date:** 2026-05-31  
**Status:** Accepted

## Context

The backend is deployed to a Kubernetes cluster. An unguarded deploy-on-push workflow risks pushing broken images directly to the user-facing production environment. We needed a gate that validates the image on real infrastructure before promoting it.

## Decision

The `backend-deploy.yml` workflow deploys in two sequential stages:

1. **Staging** (`fasttrack-staging` namespace) — runs immediately after a successful image build. Uses the `staging` GitHub environment (can require reviewers).
2. **Production** (`fasttrack-production` namespace) — gated on staging success. Uses the `production` GitHub environment (should require manual approval for critical changes).

Both stages share a reusable composite action (`.github/actions/k8s-deploy`) that handles:
- `kubeconfig` setup
- Secret sync from GitHub CI secrets to the cluster (merge-patch, non-destructive)
- GHCR pull secret rotation
- `kustomize edit set image` + `kubectl apply -k` + rollout status check

## Options considered

| Option | Pros | Cons |
|--------|------|------|
| Direct deploy to production | Simple | No validation gate; high blast radius |
| Blue/green with separate clusters | Zero-downtime; easy rollback | Complex; expensive for a small project |
| Staged deploy to same cluster (chosen) | Meaningful validation; low overhead; GitHub Environments provide approval gate | Staging shares cluster resources with production |

## Consequences

### Positive
- Production deploys are gated on staging success.
- GitHub Environments allow mandatory reviewers and deployment logs.
- The composite action eliminates copy-paste between staging and production jobs.
- Non-empty cluster secrets are preserved when CI secrets are absent (safe for rotation).

### Negative / trade-offs
- Staging and production share a cluster; a cluster-level outage blocks both.
- Secret sync is one-way (CI → cluster); manual cluster edits may be overwritten on the next deploy.

## References

- `.github/workflows/backend-deploy.yml`
- `.github/actions/k8s-deploy/action.yml`
- `backend/k8s/overlays/staging/`
- `backend/k8s/overlays/production/`
- `docs/DEPLOYMENT.md`

# Incident: 2026-06-02 PostgreSQL Cleanup + Naming Remediation

## Summary

During routine K8s cleanup, the shared PostgreSQL instance (`fastpass-postgres` in `default` namespace)
was identified as orphaned because its `fastpass-` prefix didn't match the `fasttrack-` prefix used
in manifests and API namespaces. Both `fasttrack-production` and `fasttrack-staging` API deployments
were connected to it via `fasttrack-secrets` without any documented dependency.

## Timeline

| Time | Event |
|------|-------|
| 03:34 UTC | Postgres PV/PVC/deployment deleted during cleanup |
| 03:34 UTC | API pods crash-loop — "failed to create user" errors |
| 03:34 UTC | Postgres recreated pointing to /data/fasttrack/postgres (new/empty data) |
| 03:36 UTC | Discovered real data at /data/fastpass/postgres |
| 03:38 UTC | Postgres recreated pointing to /data/fastpass/postgres |
| 03:41 UTC | Fastpass user + databases recreated, GORM auto-migrate ran |
| 03:42 UTC | API pods healthy again — but user data was empty (new schema) |
| 03:51 UTC | Discovered old data at /data/fastpass/postgres via pg-inspect |
| 03:54 UTC | Postgres switched to old data path — 2 users restored |
| 04:30-04:45 UTC | All resources renamed from fastpass- to fasttrack- prefix |

## Root Causes

1. **Name mismatch** — manifests used `fasttrack-` but deployed resources used `fastpass-`.
2. **Undocumented shared dependency** — nowhere mentioned that production + staging share a postgres.
3. **No backup validation** — backup CronJob existed but targeted wrong database/user/service.

## Remediations

### K8s resource rename (fastpass- to fasttrack-)
- PVs: `fastpass-postgres-pv` → `fasttrack-postgres-pv`
- PVCs: `fastpass-postgres-pvc` → `fasttrack-postgres-pvc`
- Deployment: `fastpass-postgres` → `fasttrack-postgres`
- Service: `fastpass-postgres-service` → `fasttrack-postgres-service`
- Secret: `fastpass-postgres-secret` → `fasttrack-postgres-secret`

### Ownership labels
All postgres resources now carry `app.kubernetes.io/part-of: fasttrack`.

### API secrets updated
Both `fasttrack-production/fasttrack-secrets` and `fasttrack-staging/fasttrack-secrets`
`database-url` fields updated to reference `fasttrack-postgres-service`.

### Backup CronJob fixed
Now connects to `fasttrack-postgres-service` as user `fasttrack` to dump `fasttrack_production`.

### Documentation updated
- `docs/DATABASE.md` — full rewrite with correct names, shared-dependency warning, incident retro
- `.github/copilot-instructions.md` — added CRITICAL note about shared postgres
- `backend/k8s/postgres-hostpath.yaml` — reconciled to match deployed names
- `backend/k8s/postgres.yaml` — reconciled
- `backend/k8s/secret.yaml.example` — updated
- `backend/k8s/backup-cronjob.yaml` — fixed
- `scripts/backup-restore.sh` — fixed user/database refs

## Data Loss

**Data was preserved.** Both user accounts and all drive records were recovered from the old
`/data/fastpass/postgres/pgdata` hostPath. The backup directory remains empty — no backups
had ever been successfully created due to the misconfiguration.

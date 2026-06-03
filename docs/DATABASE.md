# Database Management

FastTrack uses a single PostgreSQL 15 instance shared by both **production** (`fasttrack-production`)
and **staging** (`fasttrack-staging`) API deployments. The database runs in the `default` namespace.

---

## Connection Details

All API deployments connect via the internal DNS name `fasttrack-postgres-service.default.svc.cluster.local`.

| Environment | Host | Database | User | Password Source |
|---|---|---|---|---|
| Production | `fasttrack-postgres-service` | `fasttrack_production` | `fasttrack` | `fasttrack-postgres-secret` (postgres) + `fasttrack-secrets` (API) |
| Staging | `fasttrack-postgres-service` | `fasttrack_staging` | `fasttrack` | (same secret — shared) |

> **Important:** Both environments share the same PostgreSQL instance and credentials.
> Never delete resources in the `default` namespace prefixed with `fasttrack-postgres-*`
> without verifying that both API environments still function. See [Incident Retrospective](#incident-retrospective-2026-06-02-database-outage).

---

## Schema

Tables are versioned-migrated by `backend/internal/app/migrations.go` on API startup
(not GORM AutoMigrate — see ADR-0002).

```
users (
  id, apple_user_id, google_user_id, email, full_name,
  username, country, car_make, car_model, car_year, car_trim,
  garage, selected_car_id, is_public, avatar_url,
  car_stats_data, unit_system, color_scheme,
  auth_provider, created_at, updated_at
)

drives (
  id, user_id, start_time, end_time,
  start_latitude, start_longitude, end_latitude, end_longitude,
  distance, duration, max_speed, min_speed, avg_speed, route_data,
  car_id, car_make, car_model, car_year, car_trim, car_nickname,
  stopped_time, left_turns, right_turns, brake_events, lane_changes,
  max_acceleration, max_deceleration, peak_g_force, top_corner_speed,
  best_060_time, created_at, updated_at
)

follows (
  id, follower_id, following_id, created_at
)

user_achievements (
  id, user_id, achievement_type, achieved_at, metadata
)
```

---

## Storage

```
PVC                              Size  Host path                    Reclaim
fasttrack-postgres-pvc           20GB  /data/fastpass/postgres       Retain
fasttrack-postgres-backup-pvc    10GB  /data/fastpass/backups       Retain
```

Both PVs use `hostPath` on node `gigabyte` with `persistentVolumeReclaimPolicy: Retain`.
Deleting the PVC/PV will **not** delete the underlying data on disk, but the database will be
unavailable to the API until the PV is recreated pointing to the same path.

Every postgres resource carries the label `app.kubernetes.io/part-of: fasttrack` to make
ownership explicit.

---

## Backup & Restore

### Automated backups

A K8s CronJob runs `pg_dump` of the `fasttrack_production` database daily at **2 AM UTC**,
saves gzipped SQL to the backup PVC, and retains 30 days.

```bash
# Check CronJob status
kubectl get cronjob fasttrack-postgres-backup

# View recent backup jobs
kubectl get jobs -l app=fasttrack-postgres-backup

# Trigger a manual backup run
kubectl create job --from=cronjob/fasttrack-postgres-backup manual-backup-$(date +%s)

# Check backup job logs
kubectl logs job/<job-name>
```

### Manual backup

```bash
./scripts/backup-restore.sh backup
```

### List backups

```bash
./scripts/backup-restore.sh list
```

### Restore from backup (overwrites current data!)

```bash
./scripts/backup-restore.sh restore fasttrack_backup_YYYYMMDD_HHMMSS.sql.gz
```

### Download backup to local machine

```bash
./scripts/backup-restore.sh download fasttrack_backup_YYYYMMDD_HHMMSS.sql.gz
```

### Upload local backup to server

```bash
./scripts/backup-restore.sh upload my_local_backup.sql.gz
./scripts/backup-restore.sh restore my_local_backup.sql.gz
```

### Test database connection

```bash
./scripts/backup-restore.sh test
```

### Clean backups older than 30 days

```bash
./scripts/backup-restore.sh clean
```

---

## Direct Database Access

```bash
# Interactive psql session (production)
kubectl exec -it deployment/fasttrack-postgres -- psql -U fasttrack -d fasttrack_production

# Staging
kubectl exec -it deployment/fasttrack-postgres -- psql -U fasttrack -d fasttrack_staging

# Run a query
kubectl exec -it deployment/fasttrack-postgres -- \
  psql -U fasttrack -d fasttrack_production -c "SELECT COUNT(*) FROM drives;"

# Check database size
kubectl exec -it deployment/fasttrack-postgres -- \
  psql -U fasttrack -d fasttrack_production -c \
  "SELECT pg_size_pretty(pg_database_size('fasttrack_production'));"
```

---

## Monitoring

```bash
# Check pod health
kubectl get pods -l app=fasttrack-postgres
kubectl logs -f deployment/fasttrack-postgres
kubectl top pod -l app=fasttrack-postgres

# Check PVC usage
kubectl get pvc | grep fasttrack-postgres
kubectl describe pvc fasttrack-postgres-pvc

# View active connections
kubectl exec -it deployment/fasttrack-postgres -- \
  psql -U fasttrack -d fasttrack_production -c \
  "SELECT pid, usename, application_name, state FROM pg_stat_activity WHERE datname = 'fasttrack_production';"
```

---

## Password Rotation

```bash
NEW_PASSWORD=$(openssl rand -base64 24)

kubectl delete secret fasttrack-postgres-secret
kubectl create secret generic fasttrack-postgres-secret \
  --from-literal=postgres-password="$NEW_PASSWORD"

kubectl delete secret fasttrack-secrets -n fasttrack-production
kubectl create secret generic fasttrack-secrets -n fasttrack-production \
  --from-literal=database-url="host=fasttrack-postgres-service user=fasttrack password=$NEW_PASSWORD dbname=fasttrack_production port=5432 sslmode=disable" \
  --from-literal=jwt-secret="$(openssl rand -base64 32)"

kubectl delete secret fasttrack-secrets -n fasttrack-staging
kubectl create secret generic fasttrack-secrets -n fasttrack-staging \
  --from-literal=database-url="host=fasttrack-postgres-service user=fasttrack password=$NEW_PASSWORD dbname=fasttrack_staging port=5432 sslmode=disable" \
  --from-literal=jwt-secret="$(openssl rand -base64 32)"

kubectl rollout restart deployment/fasttrack-postgres
kubectl rollout restart deployment/fasttrack-api -n fasttrack-production
kubectl rollout restart deployment/fasttrack-api -n fasttrack-staging
```

---

## Expanding Storage

```bash
# Edit PVC to increase size
kubectl edit pvc fasttrack-postgres-pvc
# Change storage: 20Gi -> e.g. 50Gi, save
kubectl get pvc fasttrack-postgres-pvc -w  # watch for resize
```

---

## Migrating to External PostgreSQL

```bash
# 1. Backup
./scripts/backup-restore.sh backup && ./scripts/backup-restore.sh download <file>

# 2. Restore to external host
gunzip -c <file> | psql -h EXTERNAL_HOST -U USER -d fasttrack_production

# 3. Update secret (both environments)
kubectl delete secret fasttrack-secrets -n fasttrack-production
kubectl create secret generic fasttrack-secrets -n fasttrack-production \
  --from-literal=database-url="host=EXTERNAL_HOST user=USER password=PASS dbname=fasttrack_production port=5432 sslmode=require" \
  --from-literal=jwt-secret="YOUR_JWT_SECRET"

kubectl delete secret fasttrack-secrets -n fasttrack-staging
kubectl create secret generic fasttrack-secrets -n fasttrack-staging \
  --from-literal=database-url="host=EXTERNAL_HOST user=USER password=PASS dbname=fasttrack_staging port=5432 sslmode=require" \
  --from-literal=jwt-secret="YOUR_JWT_SECRET"

# 4. Restart API
kubectl rollout restart deployment/fasttrack-api -n fasttrack-production
kubectl rollout restart deployment/fasttrack-api -n fasttrack-staging
```

---

## Troubleshooting

### Pod in CrashLoopBackOff
```bash
kubectl describe pod -l app=fasttrack-postgres
kubectl logs -l app=fasttrack-postgres
```
Common causes: PVC not bound, wrong password secret, insufficient resources.

### PVC not bound
```bash
# This cluster uses hostPath PVs (no storage class). Apply:
kubectl apply -f backend/k8s/postgres-hostpath.yaml
```

### Password mismatch between API and PostgreSQL
```bash
# Decode both and compare
kubectl get secret fasttrack-postgres-secret -o jsonpath='{.data.postgres-password}' | base64 -d && echo
kubectl get secret fasttrack-secrets -n fasttrack-production -o jsonpath='{.data.database-url}' | base64 -d && echo
# Fix by following Password Rotation steps above
```

### Out of disk space
```bash
kubectl exec -it deployment/fasttrack-postgres -- df -h
./scripts/backup-restore.sh clean
# Then expand PVC if needed
```

---

## Incident Retrospective: 2026-06-02 Database Outage

### What happened
A K8s cleanup session deleted the shared PostgreSQL instance and its PVs/PVCs because
the resources were prefixed `fastpass-` (unrelated to `fasttrack-` in manifests), making
them look like orphaned resources from a previous project.

### Root causes
1. **Name mismatch** — deployed resources used `fastpass-` prefix while manifests used
   `fasttrack-`, creating the illusion they were separate projects.
2. **Undocumented dependency** — nowhere did it state that `fasttrack-production` and
   `fasttrack-staging` share a postgres instance in the `default` namespace.
3. **No backup validation** — the backup CronJob existed but was misconfigured
   (wrong database name, wrong user, wrong service host), so no backups were ever created.

### Remediations applied
1. **Unified naming** — all resources renamed to `fasttrack-` prefix.
2. **Ownership labels** — every postgres resource carries `app.kubernetes.io/part-of: fasttrack`.
3. **This document** — now accurately reflects the shared database architecture.
4. **Backup CronJob fixed** — now dumps the correct database (`fasttrack_production`)
   via the correct service host and user.
5. **`backup-restore.sh` fixed** — uses `fasttrack` user and `fasttrack_production` database.

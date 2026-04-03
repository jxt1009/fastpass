# Database Management

FastTrack uses a dedicated PostgreSQL 15 instance, isolated from other services on the cluster.

---

## Connection Details (in-cluster)

| Field | Value |
|---|---|
| Host | `fasttrack-postgres-service` |
| Port | `5432` |
| Database | `fasttrack` |
| User | `fasttrack` |
| Password | stored in `fasttrack-postgres-secret` K8s secret |

---

## Schema

Tables are auto-migrated by GORM on API startup.

```sql
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
```

---

## Storage

```
PVC                              Size  Host path
fasttrack-postgres-pvc           20GB  /data/fasttrack/postgres
fasttrack-postgres-backup-pvc    10GB  /data/fasttrack/backups
```

---

## Backup & Restore

### Manual backup
```bash
./backup-restore.sh backup
```

### List backups
```bash
./backup-restore.sh list
```

### Restore from backup (overwrites current data!)
```bash
./backup-restore.sh restore fasttrack_backup_YYYYMMDD_HHMMSS.sql.gz
```

### Download backup to local machine
```bash
./backup-restore.sh download fasttrack_backup_YYYYMMDD_HHMMSS.sql.gz
```

### Upload local backup to server
```bash
./backup-restore.sh upload my_local_backup.sql.gz
./backup-restore.sh restore my_local_backup.sql.gz
```

### Test database connection
```bash
./backup-restore.sh test
```

### Clean backups older than 30 days
```bash
./backup-restore.sh clean
```

---

## Automated Backups

A K8s CronJob runs `pg_dump` daily at **2 AM UTC**, saves gzipped SQL to the backup PVC, and deletes files older than 30 days.

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

---

## Direct Database Access

```bash
# Interactive psql session
kubectl exec -it deployment/fasttrack-postgres -- psql -U fasttrack -d fasttrack

# Run a query
kubectl exec -it deployment/fasttrack-postgres -- \
  psql -U fasttrack -d fasttrack -c "SELECT COUNT(*) FROM drives;"

# Check database size
kubectl exec -it deployment/fasttrack-postgres -- \
  psql -U fasttrack -d fasttrack -c \
  "SELECT pg_size_pretty(pg_database_size('fasttrack'));"
```

---

## Monitoring

```bash
# Check pod health
kubectl get pods -l app=fasttrack-postgres
kubectl logs -f deployment/fasttrack-postgres
kubectl top pod -l app=fasttrack-postgres

# Check PVC usage
kubectl get pvc | grep fasttrack
kubectl describe pvc fasttrack-postgres-pvc

# View active connections
kubectl exec -it deployment/fasttrack-postgres -- \
  psql -U fasttrack -d fasttrack -c \
  "SELECT pid, usename, application_name, state FROM pg_stat_activity WHERE datname = 'fasttrack';"
```

---

## Password Rotation

```bash
NEW_PASSWORD=$(openssl rand -base64 24)

kubectl delete secret fasttrack-postgres-secret
kubectl create secret generic fasttrack-postgres-secret \
  --from-literal=postgres-password="$NEW_PASSWORD"

kubectl delete secret fasttrack-secrets
kubectl create secret generic fasttrack-secrets \
  --from-literal=database-url="host=fasttrack-postgres-service user=fasttrack password=$NEW_PASSWORD dbname=fasttrack port=5432 sslmode=disable" \
  --from-literal=jwt-secret="$(openssl rand -base64 32)"

kubectl rollout restart deployment/fasttrack-postgres
kubectl rollout restart deployment/fasttrack-api
```

---

## Expanding Storage

```bash
# Edit PVC to increase size
kubectl edit pvc fasttrack-postgres-pvc
# Change storage: 20Gi → e.g. 50Gi, save
kubectl get pvc fasttrack-postgres-pvc -w  # watch for resize
```

---

## Migrating to External PostgreSQL

```bash
# 1. Backup
./backup-restore.sh backup && ./backup-restore.sh download <file>

# 2. Restore to external host
gunzip -c <file> | psql -h EXTERNAL_HOST -U USER -d fasttrack

# 3. Update secret
kubectl delete secret fasttrack-secrets
kubectl create secret generic fasttrack-secrets \
  --from-literal=database-url="host=EXTERNAL_HOST user=USER password=PASS dbname=fasttrack port=5432 sslmode=require" \
  --from-literal=jwt-secret="YOUR_JWT_SECRET"

# 4. Restart API
kubectl rollout restart deployment/fasttrack-api
```

---

## Troubleshooting

### Pod in CrashLoopBackOff
```bash
kubectl describe pod -l app=fasttrack-postgres
kubectl logs -l app=fasttrack-postgres
# Common causes: PVC not bound, wrong password secret, insufficient resources
```

### PVC not bound
```bash
kubectl get storageclass
# Edit postgres yaml to set correct storageClassName, or use postgres-hostpath.yaml
kubectl apply -f backend/k8s/postgres-hostpath.yaml
```

### Password mismatch between API and PostgreSQL
```bash
# Decode both and compare
kubectl get secret fasttrack-postgres-secret -o jsonpath='{.data.postgres-password}' | base64 -d && echo
kubectl get secret fasttrack-secrets -o jsonpath='{.data.database-url}' | base64 -d && echo
# Fix by following Password Rotation steps above
```

### Out of disk space
```bash
kubectl exec -it deployment/fasttrack-postgres -- df -h
./backup-restore.sh clean
# Then expand PVC if needed
```

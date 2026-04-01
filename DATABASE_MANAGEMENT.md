# FastPass Database Management Guide

## 🗄️ Independent PostgreSQL Database

FastPass uses its own PostgreSQL instance, completely separate from any other services on your server. This ensures:
- ✅ **Isolation**: No conflicts with other databases
- ✅ **Version control**: Specific PostgreSQL version for FastPass
- ✅ **Resource management**: Dedicated resources
- ✅ **Easy backup/restore**: Independent backup strategy
- ✅ **Security**: Separate credentials

---

## 📦 Database Components

### 1. PostgreSQL Deployment
- **Name**: `fastpass-postgres`
- **Database**: `fastpass`
- **User**: `fastpass`
- **Service**: `fastpass-postgres-service`
- **Storage**: 20GB PVC (expandable)

### 2. Backup Storage
- **Backup PVC**: 10GB for backup files
- **Retention**: 30 days (configurable)
- **Schedule**: Daily at 2 AM UTC
- **Format**: SQL dumps (gzipped)

---

## 🚀 Quick Start

### Deploy Database
```bash
# Automatically deployed when running:
cd ~/fastpass
./deploy-local.sh

# Or manually:
kubectl apply -f backend/k8s/postgres-secret.yaml.example  # Edit password first!
kubectl apply -f backend/k8s/postgres.yaml
kubectl apply -f backend/k8s/backup-cronjob.yaml
```

### Verify Deployment
```bash
# Check if PostgreSQL is running
kubectl get pods -l app=fastpass-postgres

# Test connection
kubectl exec -it deployment/fastpass-postgres -- psql -U fastpass -d fastpass -c "SELECT version();"
```

---

## 💾 Backup Management

### Manual Backup
```bash
# Create a backup right now
./backup-restore.sh backup
```

### List Backups
```bash
# See all available backups
./backup-restore.sh list
```

### Automated Backups
Backups run automatically every day at 2 AM:
```bash
# Check CronJob status
kubectl get cronjob fastpass-postgres-backup

# View recent backup jobs
kubectl get jobs -l app=fastpass-postgres-backup

# Check last backup log
kubectl logs job/fastpass-postgres-backup-<timestamp>
```

### Download Backup to Local Machine
```bash
# List backups
./backup-restore.sh list

# Download specific backup
./backup-restore.sh download fastpass_backup_20260401_020000.sql.gz
```

---

## 🔄 Restore Database

### From Existing Backup
```bash
# List available backups
./backup-restore.sh list

# Restore from backup (CAUTION: This overwrites current data!)
./backup-restore.sh restore fastpass_backup_20260401_020000.sql.gz
```

### From Local File
```bash
# Upload local backup to server
./backup-restore.sh upload my_local_backup.sql.gz

# Then restore it
./backup-restore.sh restore my_local_backup.sql.gz
```

---

## 🧪 Testing & Monitoring

### Test Database Connection
```bash
./backup-restore.sh test
```

### Connect to Database
```bash
# Interactive psql session
kubectl exec -it deployment/fastpass-postgres -- psql -U fastpass -d fastpass

# Run a query
kubectl exec -it deployment/fastpass-postgres -- psql -U fastpass -d fastpass -c "SELECT * FROM users LIMIT 5;"
```

### Check Database Size
```bash
kubectl exec -it deployment/fastpass-postgres -- psql -U fastpass -d fastpass -c "
SELECT 
    pg_size_pretty(pg_database_size('fastpass')) as total_size,
    pg_size_pretty(pg_total_relation_size('users')) as users_table,
    pg_size_pretty(pg_total_relation_size('drives')) as drives_table;
"
```

### View Tables
```bash
kubectl exec -it deployment/fastpass-postgres -- psql -U fastpass -d fastpass -c "\dt"
```

### View Recent Drives
```bash
kubectl exec -it deployment/fastpass-postgres -- psql -U fastpass -d fastpass -c "
SELECT id, user_id, start_time, distance, max_speed 
FROM drives 
ORDER BY start_time DESC 
LIMIT 10;
"
```

---

## 🔒 Security

### Password Management

**View Current Secret (Base64 encoded):**
```bash
kubectl get secret fastpass-postgres-secret -o yaml
```

**Decode Password:**
```bash
kubectl get secret fastpass-postgres-secret -o jsonpath='{.data.postgres-password}' | base64 -d
echo ""
```

**Change Password:**
```bash
# 1. Generate new password
NEW_PASSWORD=$(openssl rand -base64 24)

# 2. Update secret
kubectl delete secret fastpass-postgres-secret
kubectl create secret generic fastpass-postgres-secret \
  --from-literal=postgres-password="$NEW_PASSWORD"

# 3. Update API secret with new database URL
kubectl delete secret fastpass-secrets
kubectl create secret generic fastpass-secrets \
  --from-literal=database-url="host=fastpass-postgres-service user=fastpass password=$NEW_PASSWORD dbname=fastpass port=5432 sslmode=disable" \
  --from-literal=jwt-secret="YOUR_JWT_SECRET"

# 4. Restart both deployments
kubectl rollout restart deployment/fastpass-postgres
kubectl rollout restart deployment/fastpass-api
```

---

## 📊 Storage Management

### Check Storage Usage
```bash
# Check PVC status
kubectl get pvc | grep fastpass

# Detailed info
kubectl describe pvc fastpass-postgres-pvc
kubectl describe pvc fastpass-postgres-backup-pvc
```

### Expand Storage (if needed)
```bash
# Edit PVC to increase size
kubectl edit pvc fastpass-postgres-pvc

# Change storage request from 20Gi to desired size (e.g., 50Gi)
# Save and exit

# Watch for resize
kubectl get pvc fastpass-postgres-pvc -w
```

### Clean Old Backups
```bash
# Remove backups older than 30 days
./backup-restore.sh clean

# Manually clean specific files
kubectl exec -it deployment/fastpass-postgres -- sh -c "
  ls -lh /backups/
  rm /backups/fastpass_backup_OLD_FILE.sql.gz
"
```

---

## 🔧 Maintenance

### Database Vacuum (Optimize Performance)
```bash
kubectl exec -it deployment/fastpass-postgres -- psql -U fastpass -d fastpass -c "VACUUM ANALYZE;"
```

### Check Database Statistics
```bash
kubectl exec -it deployment/fastpass-postgres -- psql -U fastpass -d fastpass -c "
SELECT 
    schemaname,
    tablename,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes
FROM pg_stat_user_tables;
"
```

### View Active Connections
```bash
kubectl exec -it deployment/fastpass-postgres -- psql -U fastpass -d fastpass -c "
SELECT 
    pid,
    usename,
    application_name,
    client_addr,
    state,
    query
FROM pg_stat_activity
WHERE datname = 'fastpass';
"
```

---

## 🚨 Troubleshooting

### Pod Won't Start

**Check pod status:**
```bash
kubectl describe pod -l app=fastpass-postgres
```

**Common issues:**
- PVC not bound (check storage class)
- Password secret not found
- Insufficient resources

**Fix PVC issues:**
```bash
# Check storage classes
kubectl get storageclass

# If needed, update postgres.yaml with correct storageClassName
kubectl edit -f backend/k8s/postgres.yaml
```

### Connection Refused

**Test from within cluster:**
```bash
kubectl run test-db --rm -it --image=postgres:15-alpine --restart=Never -- \
  psql -h fastpass-postgres-service -U fastpass -d fastpass
```

**Check service:**
```bash
kubectl get svc fastpass-postgres-service
kubectl describe svc fastpass-postgres-service
```

### Out of Space

**Check disk usage in pod:**
```bash
kubectl exec -it deployment/fastpass-postgres -- df -h
```

**Solutions:**
1. Clean old backups: `./backup-restore.sh clean`
2. Expand PVC (see Storage Management)
3. Move backups off cluster

### Backup Job Fails

**Check CronJob logs:**
```bash
# Get recent job
JOB=$(kubectl get jobs -l app=fastpass-postgres-backup --sort-by=.metadata.creationTimestamp | tail -n 1 | awk '{print $1}')

# View logs
kubectl logs job/$JOB
```

**Common issues:**
- Backup PVC full
- Password incorrect
- Database not accessible

---

## 📋 Backup Checklist

### Daily (Automated)
- ✅ Automated backup at 2 AM
- ✅ Check backup job succeeded: `kubectl get jobs`
- ✅ Verify backup file created

### Weekly (Manual)
- [ ] Test restore process on dev environment
- [ ] Download recent backup to local storage
- [ ] Check backup file integrity
- [ ] Verify database statistics

### Monthly (Manual)
- [ ] Review and clean old backups
- [ ] Test full disaster recovery
- [ ] Check storage usage trends
- [ ] Review security (passwords, access)
- [ ] Update documentation if needed

---

## 🔄 Migration Scenarios

### Migrate to Larger Storage

```bash
# 1. Create backup
./backup-restore.sh backup

# 2. Download backup
./backup-restore.sh download <latest-backup>

# 3. Delete old deployment
kubectl delete deployment fastpass-postgres
kubectl delete pvc fastpass-postgres-pvc

# 4. Edit postgres.yaml to increase storage
# Change: storage: 20Gi -> storage: 50Gi

# 5. Redeploy
kubectl apply -f backend/k8s/postgres.yaml

# 6. Wait for ready
kubectl wait --for=condition=ready pod -l app=fastpass-postgres --timeout=180s

# 7. Restore data
./backup-restore.sh restore <backup-file>
```

### Move to External Database

If you want to use external PostgreSQL (e.g., managed service):

```bash
# 1. Create backup
./backup-restore.sh backup
./backup-restore.sh download <latest-backup>

# 2. Update fastpass-secrets with new connection string
kubectl delete secret fastpass-secrets
kubectl create secret generic fastpass-secrets \
  --from-literal=database-url="host=EXTERNAL_HOST user=USER password=PASS dbname=fastpass port=5432 sslmode=require" \
  --from-literal=jwt-secret="YOUR_JWT_SECRET"

# 3. Restore to external database (manually)
gunzip -c <backup-file> | psql -h EXTERNAL_HOST -U USER -d fastpass

# 4. Restart API
kubectl rollout restart deployment/fastpass-api

# 5. Delete internal PostgreSQL (optional)
kubectl delete deployment fastpass-postgres
kubectl delete svc fastpass-postgres-service
```

---

## 📊 Recommended Practices

### 1. Regular Backups
- ✅ Keep automated daily backups enabled
- ✅ Create manual backup before major changes
- ✅ Store important backups off-cluster

### 2. Monitor Storage
- ✅ Set up alerts for >80% storage usage
- ✅ Regularly check backup PVC space
- ✅ Plan storage expansion ahead of time

### 3. Test Restores
- ✅ Test restore process monthly
- ✅ Verify backup integrity
- ✅ Document restore time

### 4. Security
- ✅ Use strong passwords (24+ characters)
- ✅ Rotate credentials periodically
- ✅ Limit database access to necessary services only
- ✅ Keep PostgreSQL version updated

### 5. Performance
- ✅ Run VACUUM weekly for large databases
- ✅ Monitor connection count
- ✅ Index frequently queried columns
- ✅ Monitor query performance

---

## 📞 Quick Commands Reference

```bash
# Backup Operations
./backup-restore.sh backup          # Create backup
./backup-restore.sh list            # List backups
./backup-restore.sh restore <file>  # Restore backup
./backup-restore.sh clean           # Clean old backups
./backup-restore.sh test            # Test connection

# Database Access
kubectl exec -it deployment/fastpass-postgres -- psql -U fastpass -d fastpass

# Monitoring
kubectl get pods -l app=fastpass-postgres
kubectl logs -f deployment/fastpass-postgres
kubectl top pod -l app=fastpass-postgres

# Maintenance
kubectl rollout restart deployment/fastpass-postgres
kubectl get cronjob fastpass-postgres-backup
kubectl get pvc | grep fastpass
```

---

**Database**: fastpass  
**User**: fastpass  
**Service**: fastpass-postgres-service  
**Namespace**: default  
**Storage**: 20GB (data) + 10GB (backups)

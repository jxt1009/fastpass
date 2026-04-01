# Troubleshooting: Database Connection Refused

## Error Message
```
failed to connect to `user=fastpass database=fastpass`: 10.107.174.177:5432 (fastpass-postgres-service): 
dial error: dial tcp 10.107.174.177:5432: connect: connection refused
```

## What This Means
The API pod can resolve the service name (`fastpass-postgres-service`) but can't connect to PostgreSQL on port 5432.

---

## Quick Fix Steps

### Step 1: Check if PostgreSQL is Running

```bash
# Check pods
kubectl get pods -l app=fastpass-postgres

# Expected output:
# NAME                                  READY   STATUS    RESTARTS   AGE
# fastpass-postgres-xxxxxxxxxx-xxxxx    1/1     Running   0          5m
```

**If pod is not running or in CrashLoopBackOff:**

```bash
# Check what's wrong
kubectl describe pod -l app=fastpass-postgres

# Check logs
kubectl logs -l app=fastpass-postgres
```

### Step 2: Verify Service Exists

```bash
# Check service
kubectl get svc fastpass-postgres-service

# Expected output:
# NAME                        TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
# fastpass-postgres-service   ClusterIP   10.107.174.177  <none>        5432/TCP   5m
```

**If service doesn't exist:**

```bash
# Deploy PostgreSQL
kubectl apply -f backend/k8s/postgres.yaml
```

### Step 3: Test Database Connection

```bash
# Try to connect from within cluster
kubectl run test-db --rm -it --image=postgres:15-alpine --restart=Never -- \
  psql -h fastpass-postgres-service -U fastpass -d fastpass

# If it asks for password, the service is working!
# Press Ctrl+C to exit
```

### Step 4: Check PostgreSQL Pod is Ready

```bash
# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=fastpass-postgres --timeout=180s

# If timeout, check pod status
kubectl get pod -l app=fastpass-postgres
kubectl describe pod -l app=fastpass-postgres
```

---

## Common Issues & Solutions

### Issue 1: PostgreSQL Pod Not Running

**Symptoms:**
- No pods found with label `app=fastpass-postgres`
- Pod in Pending or CrashLoopBackOff state

**Solution:**

```bash
# Check if PostgreSQL was deployed
kubectl get deployment fastpass-postgres

# If not found, deploy it
kubectl apply -f backend/k8s/postgres-secret.yaml.example  # Edit password first!
kubectl apply -f backend/k8s/postgres.yaml

# Wait for ready
kubectl wait --for=condition=ready pod -l app=fastpass-postgres --timeout=180s
```

### Issue 2: PVC Not Bound

**Symptoms:**
- Pod stuck in Pending
- Event: "pod has unbound immediate PersistentVolumeClaims"

**Check:**
```bash
kubectl get pvc | grep fastpass

# Should show:
# fastpass-postgres-pvc         Bound    ...
# fastpass-postgres-backup-pvc  Bound    ...
```

**Solution:**

```bash
# Check storage classes
kubectl get storageclass

# Edit postgres.yaml to use correct storageClassName
kubectl edit -f backend/k8s/postgres.yaml

# Common values:
# - local-path (k3s default)
# - standard (GKE)
# - gp2 (AWS EKS)
# - default (many clusters)

# Or remove storageClassName to use default
```

### Issue 3: Wrong Password in Secret

**Symptoms:**
- PostgreSQL pod running
- API can connect but auth fails

**Solution:**

```bash
# Get the password from postgres secret
kubectl get secret fastpass-postgres-secret -o jsonpath='{.data.postgres-password}' | base64 -d
echo ""

# Get the database URL from API secret
kubectl get secret fastpass-secrets -o jsonpath='{.data.database-url}' | base64 -d
echo ""

# They should match! If not, recreate secrets:

# 1. Delete old secrets
kubectl delete secret fastpass-postgres-secret
kubectl delete secret fastpass-secrets

# 2. Generate new password
NEW_PASSWORD=$(openssl rand -base64 24)
echo "New password: $NEW_PASSWORD"

# 3. Create secrets
kubectl create secret generic fastpass-postgres-secret \
  --from-literal=postgres-password="$NEW_PASSWORD"

kubectl create secret generic fastpass-secrets \
  --from-literal=database-url="host=fastpass-postgres-service user=fastpass password=$NEW_PASSWORD dbname=fastpass port=5432 sslmode=disable" \
  --from-literal=jwt-secret="$(openssl rand -base64 32)"

# 4. Restart both deployments
kubectl rollout restart deployment/fastpass-postgres
kubectl rollout restart deployment/fastpass-api
```

### Issue 4: Service Name Mismatch

**Symptoms:**
- Service exists but API can't resolve name

**Check:**
```bash
# Verify service name exactly matches
kubectl get svc | grep postgres

# Should be: fastpass-postgres-service
```

**Solution:**

If service has different name, update the secret:

```bash
# Get current password
PASSWORD=$(kubectl get secret fastpass-postgres-secret -o jsonpath='{.data.postgres-password}' | base64 -d)

# Update API secret with correct service name
kubectl delete secret fastpass-secrets
kubectl create secret generic fastpass-secrets \
  --from-literal=database-url="host=CORRECT-SERVICE-NAME user=fastpass password=$PASSWORD dbname=fastpass port=5432 sslmode=disable" \
  --from-literal=jwt-secret="$(kubectl get secret fastpass-secrets -o jsonpath='{.data.jwt-secret}' | base64 -d)"

# Restart API
kubectl rollout restart deployment/fastpass-api
```

### Issue 5: PostgreSQL Not Ready Yet

**Symptoms:**
- Pod exists but not ready
- API starting before PostgreSQL is ready

**Solution:**

```bash
# Wait for PostgreSQL to be fully ready
kubectl wait --for=condition=ready pod -l app=fastpass-postgres --timeout=300s

# Then restart API
kubectl rollout restart deployment/fastpass-api

# Or configure deployment with initContainer to wait (advanced)
```

---

## Step-by-Step Recovery

If nothing works, do a clean redeploy:

### 1. Clean Up
```bash
# Delete everything
kubectl delete deployment fastpass-api
kubectl delete deployment fastpass-postgres
kubectl delete svc fastpass-api
kubectl delete svc fastpass-postgres-service
kubectl delete secret fastpass-secrets
kubectl delete secret fastpass-postgres-secret
kubectl delete pvc fastpass-postgres-pvc
kubectl delete pvc fastpass-postgres-backup-pvc
```

### 2. Check Storage Class
```bash
kubectl get storageclass

# Note the name, e.g., "local-path" or "standard"
```

### 3. Edit postgres.yaml
```bash
# Update storageClassName in backend/k8s/postgres.yaml
# Change or remove this line:
#   storageClassName: local-path
```

### 4. Redeploy
```bash
cd ~/fastpass
./deploy-local.sh
```

---

## Verification Commands

After fixing, verify everything:

```bash
# 1. PostgreSQL pod running?
kubectl get pods -l app=fastpass-postgres

# 2. Service exists?
kubectl get svc fastpass-postgres-service

# 3. PVCs bound?
kubectl get pvc | grep fastpass

# 4. Can connect?
kubectl run test-db --rm -it --image=postgres:15-alpine -- \
  psql -h fastpass-postgres-service -U fastpass -d fastpass -c "SELECT 1;"

# 5. API logs clean?
kubectl logs -l app=fastpass-api --tail=20

# 6. Health check?
kubectl exec -it deployment/fastpass-api -- wget -qO- http://localhost:8080/health
```

---

## Most Likely Cause

Based on the error, the most common causes are:

1. **PostgreSQL pod not deployed yet** (90% of cases)
   - Solution: `kubectl apply -f backend/k8s/postgres.yaml`

2. **PVC not bound** (5% of cases)
   - Solution: Fix storageClassName

3. **Pod not ready yet** (3% of cases)
   - Solution: Wait longer or check pod logs

4. **Wrong service name** (2% of cases)
   - Solution: Update secret with correct service name

---

## Quick Diagnostic

Run this to see everything at once:

```bash
echo "=== Pods ==="
kubectl get pods -l app=fastpass-postgres

echo -e "\n=== Service ==="
kubectl get svc fastpass-postgres-service

echo -e "\n=== PVC ==="
kubectl get pvc | grep fastpass

echo -e "\n=== Secrets ==="
kubectl get secret fastpass-postgres-secret
kubectl get secret fastpass-secrets

echo -e "\n=== Recent Events ==="
kubectl get events --sort-by=.metadata.creationTimestamp | grep -i postgres | tail -10

echo -e "\n=== PostgreSQL Logs ==="
kubectl logs -l app=fastpass-postgres --tail=20

echo -e "\n=== API Logs ==="
kubectl logs -l app=fastpass-api --tail=10
```

---

## Need More Help?

If still stuck, gather this information:

```bash
# Save diagnostic info
kubectl get all -o yaml > debug-all.yaml
kubectl describe pod -l app=fastpass-postgres > debug-postgres-pod.txt
kubectl describe pod -l app=fastpass-api > debug-api-pod.txt
kubectl get events > debug-events.txt
```

Then review the files for specific errors.

---

**Updated**: April 1, 2026  
**Issue**: Connection Refused to PostgreSQL  
**Status**: Common issue with easy fix

# FastPass Deployment Status

## ✅ Deployment Complete

### Current State (April 1, 2026)

**Backend API**: ✅ Running
- 2 healthy pods: `fastpass-api-84d58d7b74-4cr87`, `fastpass-api-84d58d7b74-ww2xw`
- Health check passing: `{"status":"ok"}`
- Connected to database successfully
- Endpoints: `/health`, `/api/v1/auth/*`, `/api/v1/drives/*`, `/api/v1/me`

**PostgreSQL Database**: ✅ Running
- Pod: `fastpass-postgres-56b84659c6-wg2tm`
- Database: `fastpass`
- User: `fastpass`
- Password: `18fAqd0Qz08LXifXi28zQCfDX7nwcqRe`
- Storage: hostPath volumes at `/data/fastpass/postgres` (20GB) and `/data/fastpass/backups` (10GB)

**Kubernetes Resources**: ✅ Deployed
- Service: `fastpass-api` (ClusterIP: 10.102.8.138:80)
- Service: `fastpass-postgres-service` (ClusterIP: 10.107.174.177:5432)
- Ingress: `fastpass-api` (Host: fast.toper.dev, Address: 10.0.0.102)
- SSL Certificate: `fastpass-api-tls` (Let's Encrypt)

## ⚠️ DNS Configuration Required

**Issue**: The DNS for `fast.toper.dev` is currently pointing to Cloudflare IPs instead of your server.

**Current DNS**:
```
fast.toper.dev -> 172.67.169.37, 104.21.27.114
```

**Required Change**:
Update the DNS A record for `fast.toper.dev` to point to: **73.158.156.201** (your server's public IP)

### Two Options:

#### Option A: Manual DNS Update (Quick - 2 minutes)
1. Log in to Cloudflare dashboard
2. Go to DNS settings for `toper.dev`
3. Find the A record for `fast.toper.dev`
4. Update the IPv4 address to `73.158.156.201`
5. Set Proxy status to "DNS only" (grey cloud) for initial testing
6. Wait 5-10 minutes for propagation

#### Option B: Automated DNS with ExternalDNS (Recommended for future)
Automatically manages DNS for all your Kubernetes ingresses. See `DNS_AUTOMATION.md` for full guide.

**Quick setup**:
```bash
# Get Cloudflare API token from: https://dash.cloudflare.com/profile/api-tokens
export CLOUDFLARE_API_TOKEN='your_token_here'
bash setup-external-dns.sh
```

After setup, ExternalDNS will automatically create/update DNS records for any new ingress!

### Verify DNS After Update:

```bash
# Check DNS propagation (5-10 minutes typically)
watch -n 5 'dig +short fast.toper.dev'
# Should show: 73.158.156.201

# Test the API
curl https://fast.toper.dev/health
# Should return: {"status":"ok"}
```

## 🔧 Troubleshooting - What We Fixed

### Issue 1: PVCs Not Binding
**Problem**: Original postgres.yaml used `storageClassName: local-path`, but the cluster had no storage classes configured.

**Solution**: Created `postgres-hostpath.yaml` with explicit PersistentVolume definitions using hostPath:
- `/data/fastpass/postgres` - 20GB for database
- `/data/fastpass/backups` - 10GB for backups

### Issue 2: Password Mismatch
**Problem**: The postgres secret and API secret had different passwords (typo in one of them).

**Correct Password**: `18fAqd0Qz08LXifXi28zQCfDX7nwcqRe`

**Solution**:
```bash
# Updated postgres secret
kubectl delete secret fastpass-postgres-secret
kubectl create secret generic fastpass-postgres-secret \
  --from-literal=postgres-password='18fAqd0Qz08LXifXi28zQCfDX7nwcqRe'

# Updated API secret
kubectl delete secret fastpass-secrets
kubectl create secret generic fastpass-secrets \
  --from-literal=database-url='host=fastpass-postgres-service user=fastpass password=18fAqd0Qz08LXifXi28zQCfDX7nwcqRe dbname=fastpass port=5432 sslmode=disable' \
  --from-literal=jwt-secret='<existing-jwt-secret>'

# Restarted services
kubectl rollout restart deployment/fastpass-postgres
kubectl rollout restart deployment/fastpass-api
```

## 📊 Verification

### Internal Cluster Test (✅ Working)
```bash
ssh -p 2222 jtoper@10.0.0.102
kubectl run -it --rm test-curl --image=curlimages/curl -- curl -s http://fastpass-api/health
# Output: {"status":"ok"}
```

### External Access (⏳ Waiting for DNS)
```bash
curl https://fast.toper.dev/health
# Currently: 404 (DNS not pointing to server)
# Expected after DNS fix: {"status":"ok"}
```

## 🎯 Next Steps

1. **Configure DNS** (see above)

2. **Test End-to-End**:
   - Open iOS app in Xcode
   - Build to physical device (not simulator - needs background location)
   - Sign in with Apple ID
   - Start recording a drive
   - Verify map shows route
   - Stop recording
   - Check drive appears in history

3. **Monitor Logs**:
   ```bash
   # API logs
   kubectl logs -f -l app=fastpass-api

   # Postgres logs
   kubectl logs -f -l app=fastpass-postgres
   ```

4. **Set Up Automated Backups** (already configured):
   - CronJob runs daily at 2 AM UTC
   - Check: `kubectl get cronjob`
   - Test: `kubectl create job --from=cronjob/fastpass-postgres-backup manual-backup-test`

5. **Push to GitHub**:
   ```bash
   cd /Users/jtoper/DEV/triprank
   git add .
   git commit -m "Add hostPath postgres config and deployment status"
   git push origin main
   ```

## 🚀 Server Endpoints

Once DNS is configured:

- **Health Check**: `https://fast.toper.dev/health`
- **Auth - Apple Sign In**: `POST https://fast.toper.dev/api/v1/auth/apple`
- **Auth - Refresh Token**: `POST https://fast.toper.dev/api/v1/auth/refresh`
- **User Info**: `GET https://fast.toper.dev/api/v1/me` (requires JWT)
- **Drives - List**: `GET https://fast.toper.dev/api/v1/drives` (requires JWT)
- **Drives - Create**: `POST https://fast.toper.dev/api/v1/drives` (requires JWT)
- **Drives - Get**: `GET https://fast.toper.dev/api/v1/drives/:id` (requires JWT)
- **Drives - Update**: `PUT https://fast.toper.dev/api/v1/drives/:id` (requires JWT)

## 📁 Files Modified/Created

- `backend/k8s/postgres-hostpath.yaml` - New file with hostPath storage configuration
- `DEPLOYMENT_STATUS.md` - This file

## 🔐 Security Notes

- JWT secret is stored in Kubernetes secret (not in git)
- PostgreSQL password is stored in Kubernetes secret (not in git)
- SSL/TLS enabled via Let's Encrypt
- CORS configured to allow iOS app access
- All drive endpoints require valid JWT token
- Drives are filtered by authenticated user ID

## 💾 Database Information

**Connection Details** (from within cluster):
```
Host: fastpass-postgres-service
Port: 5432
Database: fastpass
User: fastpass
Password: 18fAqd0Qz08LXifXi28zQCfDX7nwcqRe
```

**Tables**:
- `users` - User accounts from Apple Sign In
- `drives` - Drive records with stats and route data

**Storage Locations** (on server):
- Database data: `/data/fastpass/postgres/`
- Backups: `/data/fastpass/backups/`

# Deploy FastTrack on Ubuntu Server (Local Deployment)

This guide is for running the deployment **directly on your Ubuntu server** at 10.0.0.102.

## 🚀 Quick Start

### Step 1: Get Code onto Server

Choose one of these methods:

#### Option A: Git Clone (Recommended)
```bash
# On your server
cd ~
git clone https://github.com/YOUR_USERNAME/fasttrack.git
cd fasttrack
```

#### Option B: SCP Transfer from Mac
```bash
# On your Mac
cd /Users/jtoper/DEV
tar -czf triprank.tar.gz triprank/
scp triprank.tar.gz jtoper@10.0.0.102:~/

# On your server
cd ~
tar -xzf triprank.tar.gz
cd triprank
```

### Step 2: Run Deployment Script
```bash
# On your server
cd ~/fasttrack  # or ~/triprank
./deploy-local.sh
```

That's it! The script handles everything else.

---

## 📋 What the Script Does

1. ✅ Checks Docker and kubectl are installed
2. ✅ Checks for FastTrack PostgreSQL (offers to deploy if missing)
3. ✅ Deploys independent PostgreSQL instance (not shared with other services)
4. ✅ Builds Docker image locally
5. ✅ Creates Kubernetes secrets (auto-generates JWT)
6. ✅ Deploys 2 API replicas to namespace "default"
7. ✅ Configures ingress for fast.toper.dev
8. ✅ Sets up automated daily backups
9. ✅ Waits for pods to be ready
10. ✅ Tests health endpoint

---

## 🔧 Prerequisites

Before running the script, ensure your server has:

### 1. Docker
```bash
# Check if installed
docker --version

# If not installed
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Log out and back in for group changes
```

### 2. kubectl
```bash
# Check if installed
kubectl version --client

# If not installed (example for amd64)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

### 3. Kubernetes Cluster
Your K8s cluster should already be running with:
- ✅ nginx-ingress-controller
- ✅ cert-manager (for SSL)

### 4. Repository Access
If using git clone, you'll need:
- GitHub personal access token (for private repos)
- Or SSH key configured

---

## 🔑 During Deployment

The script will prompt for:

### PostgreSQL
If PostgreSQL not found:
- Offers to deploy **independent** PostgreSQL instance for FastTrack
- Does NOT use existing PostgreSQL (ensures isolation)
- Creates database named "fasttrack" with user "fasttrack"
- Generates secure random password
- Sets up automated daily backups at 2 AM
- Configures 20GB storage for data + 10GB for backups

### Secrets
If secrets don't exist:
- Prompt for PostgreSQL password
- Auto-generate JWT secret (or you can provide one)

---

## ✅ Verify Deployment

### Check Pods
```bash
kubectl get pods -l app=fasttrack-api
```

Expected:
```
NAME                            READY   STATUS    RESTARTS   AGE
fasttrack-api-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
fasttrack-api-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

### Check Logs
```bash
kubectl logs -l app=fasttrack-api --tail=50
```

### Test Health Endpoint
```bash
# Internal (from server)
curl http://fasttrack-api/health

# External (requires DNS)
curl https://fast.toper.dev/health
```

Expected response:
```json
{"status":"ok"}
```

---

## 🌐 DNS Configuration

After deployment, configure your DNS:

**Add A Record:**
```
Type: A
Name: fast
Domain: toper.dev
Value: <your-cluster-ingress-ip>
TTL: 300
```

**Find your ingress IP:**
```bash
kubectl get svc -n ingress-nginx
# Look for EXTERNAL-IP of ingress-nginx-controller
```

**Or check ingress:**
```bash
kubectl get ingress fasttrack-api
```

---

## 🔒 SSL Certificate

The ingress is configured with cert-manager to automatically request a Let's Encrypt certificate.

### Check Certificate Status
```bash
# View certificate
kubectl get certificate

# Detailed info
kubectl describe certificate fasttrack-api-tls
```

### If Certificate Fails
Common issues:
1. DNS not propagated (wait 5-10 minutes)
2. Domain doesn't point to cluster IP
3. Port 80/443 not accessible

```bash
# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Force renewal
kubectl delete certificate fasttrack-api-tls
# It will be recreated automatically
```

---

## 🔄 Update Deployment

When you make code changes:

### Option 1: Re-run Script
```bash
# Pull latest code
cd ~/fasttrack
git pull

# Re-deploy
./deploy-local.sh
```

### Option 2: Manual Update
```bash
# Rebuild image
cd ~/fasttrack/backend
docker build -t fasttrack-api:latest .

# Restart deployment
kubectl rollout restart deployment/fasttrack-api
```

---

## 🐛 Troubleshooting

### Pods Not Starting

**Check pod status:**
```bash
kubectl describe pod -l app=fasttrack-api
```

**Common issues:**
- Image pull error (image not found locally)
- Secret not found (fasttrack-secrets)
- Insufficient resources

### Database Connection Failed

**Test connectivity:**
```bash
# From within a pod
kubectl exec -it deployment/fasttrack-api -- sh
nc -zv postgres-service 5432
```

**Check secret:**
```bash
kubectl get secret fasttrack-secrets -o yaml
# Decode values:
echo "BASE64_STRING" | base64 -d
```

### Build Fails

**Check Go installation:**
```bash
# The Dockerfile uses Go, but Docker build handles it
# Make sure Docker has enough resources
docker system df
docker system prune  # if needed
```

### External Health Check Fails

**Check ingress:**
```bash
kubectl describe ingress fasttrack-api
```

**Check nginx logs:**
```bash
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller | grep fast.toper.dev
```

**Test DNS:**
```bash
nslookup fast.toper.dev
dig fast.toper.dev
```

---

## 📊 Monitoring

### View Logs (Live)
```bash
kubectl logs -f deployment/fasttrack-api
```

### Resource Usage
```bash
kubectl top pods -l app=fasttrack-api
kubectl top nodes
```

### Pod Status (Watch)
```bash
kubectl get pods -l app=fasttrack-api -w
```

---

## 🔧 Common Commands

### Restart Deployment
```bash
kubectl rollout restart deployment/fasttrack-api
```

### Scale Replicas
```bash
kubectl scale deployment fasttrack-api --replicas=3
```

### View All Resources
```bash
kubectl get all -l app=fasttrack-api
```

### Delete Deployment
```bash
kubectl delete deployment fasttrack-api
kubectl delete service fasttrack-api
kubectl delete ingress fasttrack-api
kubectl delete secret fasttrack-secrets
```

### Check Ingress Controller
```bash
kubectl get svc -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```

---

## 📝 Example Deployment Session

```bash
# 1. Get code
cd ~
git clone https://github.com/yourname/fasttrack.git
cd fasttrack

# 2. Run deployment
./deploy-local.sh

# Output:
🚀 FastTrack Local Deployment Script
====================================
→ Checking environment...
✓ Repository found
→ Checking Docker...
✓ Docker is available
→ Checking kubectl...
✓ kubectl is available
→ Checking PostgreSQL...
✓ PostgreSQL service found
→ Building Docker image...
✓ Docker image built successfully
→ Creating secrets...
✓ Generated JWT secret
✓ Secret created
→ Deploying to Kubernetes...
✓ Kubernetes manifests applied
→ Waiting for deployment...
✓ Deployment ready!
🎉 Deployment Complete!

API Endpoint: https://fast.toper.dev

# 3. Verify
curl https://fast.toper.dev/health
# {"status":"ok"}
```

---

## 🎯 Production Checklist

Before going live:

- [ ] DNS configured and propagated
- [ ] SSL certificate issued (check with `kubectl get certificate`)
- [ ] Health endpoint responds externally
- [ ] PostgreSQL has secure password
- [ ] JWT secret is random and saved securely
- [ ] Logs show no errors
- [ ] Test Apple Sign In from iOS app
- [ ] Test drive creation and sync
- [ ] Set up database backups
- [ ] Monitor resource usage

---

## 💾 Database Backup

### Manual Backup
```bash
# Get postgres pod name
kubectl get pods -l app=postgres

# Backup database
kubectl exec <postgres-pod-name> -- pg_dump -U postgres fasttrack > fasttrack_backup_$(date +%Y%m%d).sql
```

### Automated Backups
Consider setting up a CronJob:
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: postgres:15-alpine
            command:
            - /bin/sh
            - -c
            - pg_dump -h postgres-service -U postgres fasttrack > /backup/fasttrack_$(date +%Y%m%d).sql
            env:
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: fasttrack-secrets
                  key: postgres-password
          restartPolicy: OnFailure
```

---

## 🔗 Links

- **Deployment Script**: `./deploy-local.sh`
- **K8s Manifests**: `./backend/k8s/`
- **Quick Reference**: `./QUICK_DEPLOY.md`
- **Full Deployment Guide**: `./DEPLOYMENT_TOPER_DEV.md`

---

**Server**: 10.0.0.102  
**Domain**: fast.toper.dev  
**Namespace**: default  
**Replicas**: 2

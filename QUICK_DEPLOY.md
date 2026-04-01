# FastTrack Deployment Quick Reference

## 🚀 Deploy to fast.toper.dev

### Method 1: Deploy on Server (Recommended)

**Run directly on your Ubuntu server:**

```bash
# On server (10.0.0.102)
cd ~/fasttrack
./deploy-local.sh
```

See: `DEPLOY_ON_SERVER.md` for detailed guide

### Method 2: Deploy from Mac

**Run from your Mac (requires SSH access):**

```bash
# On Mac
cd /Users/jtoper/DEV/triprank
./deploy-to-toper.sh
```

---

## 📋 Quick Setup

### Get Code on Server

**Option A: Git Clone**
```bash
ssh jtoper@10.0.0.102
cd ~
git clone https://github.com/YOUR_USERNAME/fasttrack.git
cd fasttrack
./deploy-local.sh
```

**Option B: SCP Transfer**
```bash
# From Mac
cd /Users/jtoper/DEV
tar -czf triprank.tar.gz triprank/
scp triprank.tar.gz jtoper@10.0.0.102:~/

# On server
tar -xzf triprank.tar.gz
cd triprank
./deploy-local.sh
```

---

## 📋 Prerequisites

Before deploying, ensure:

- [ ] SSH access: `ssh jtoper@10.0.0.102` works
- [ ] PostgreSQL database ready (or will be created)
- [ ] Docker installed locally
- [ ] DNS: `fast.toper.dev` → your cluster IP
- [ ] nginx-ingress-controller running
- [ ] cert-manager installed (for SSL)

---

## 🔑 Required Secrets

The deployment needs two secrets:

### 1. Database URL
```
host=postgres-service user=postgres password=YOUR_PASSWORD dbname=fasttrack port=5432 sslmode=disable
```

### 2. JWT Secret
```bash
# Generate with:
openssl rand -base64 32
```

The script will prompt for these or generate them.

---

## ✅ Verify Deployment

```bash
# 1. Check pods
ssh jtoper@10.0.0.102 "kubectl get pods -l app=fasttrack-api"

# 2. Check logs
ssh jtoper@10.0.0.102 "kubectl logs -l app=fasttrack-api --tail=50"

# 3. Test health
curl https://fast.toper.dev/health

# Expected: {"status":"ok"}
```

---

## 🔧 Common Commands

### View Logs (Live)
```bash
ssh jtoper@10.0.0.102 "kubectl logs -f deployment/fasttrack-api"
```

### Restart Deployment
```bash
ssh jtoper@10.0.0.102 "kubectl rollout restart deployment/fasttrack-api"
```

### Scale Replicas
```bash
ssh jtoper@10.0.0.102 "kubectl scale deployment fasttrack-api --replicas=3"
```

### Check SSL Certificate
```bash
ssh jtoper@10.0.0.102 "kubectl get certificate fasttrack-api-tls"
```

### Delete Everything
```bash
ssh jtoper@10.0.0.102 << 'EOF'
kubectl delete deployment fasttrack-api
kubectl delete service fasttrack-api
kubectl delete ingress fasttrack-api
kubectl delete secret fasttrack-secrets
EOF
```

---

## 🐛 Troubleshooting

### Pods Not Starting
```bash
# Check pod description
ssh jtoper@10.0.0.102 "kubectl describe pod -l app=fasttrack-api"

# Check events
ssh jtoper@10.0.0.102 "kubectl get events --sort-by=.metadata.creationTimestamp"
```

### Database Connection Failed
```bash
# Test from within pod
ssh jtoper@10.0.0.102 "kubectl exec -it deployment/fasttrack-api -- nc -zv postgres-service 5432"
```

### SSL Not Working
```bash
# Check certificate status
ssh jtoper@10.0.0.102 "kubectl describe certificate fasttrack-api-tls"

# Check ingress
ssh jtoper@10.0.0.102 "kubectl describe ingress fasttrack-api"
```

Wait 2-5 minutes for Let's Encrypt to issue certificate.

### Health Check Fails
```bash
# Test internally
ssh jtoper@10.0.0.102 "kubectl run test --rm -it --image=curlimages/curl -- curl http://fasttrack-api/health"
```

---

## 📱 iOS App Configuration

After deployment, iOS app is already configured to use:

```swift
// File: ios/FastTrack/FastTrack/Services/APIService.swift
private let baseURL = "https://fast.toper.dev/api/v1"
```

### Test Endpoints

- **Health**: https://fast.toper.dev/health
- **Auth**: https://fast.toper.dev/api/v1/auth/apple
- **Drives**: https://fast.toper.dev/api/v1/drives

---

## 🔄 Update Deployment

When you make code changes:

```bash
# 1. Rebuild backend
cd /Users/jtoper/DEV/triprank/backend
go build -o fasttrack-api

# 2. Run deploy script again
cd /Users/jtoper/DEV/triprank
./deploy-to-toper.sh

# Or manually:
# - Build Docker image
# - Transfer to server
# - Restart deployment
```

---

## 📊 Monitoring

### Resource Usage
```bash
ssh jtoper@10.0.0.102 "kubectl top pods -l app=fasttrack-api"
```

### Pod Status
```bash
ssh jtoper@10.0.0.102 "kubectl get pods -l app=fasttrack-api -w"
```

### Ingress Traffic
```bash
ssh jtoper@10.0.0.102 "kubectl logs -n ingress-nginx deployment/ingress-nginx-controller | grep fast.toper.dev"
```

---

## 🎯 Production Checklist

Before going live:

- [ ] PostgreSQL has strong password
- [ ] JWT secret is randomly generated (not default)
- [ ] SSL certificate is valid (check browser)
- [ ] Health endpoint responds
- [ ] Test Apple Sign In flow
- [ ] Test drive creation and sync
- [ ] Monitor logs for errors
- [ ] Set up DNS properly
- [ ] Backup database regularly

---

## 🔗 Quick Links

- **Deployment Guide**: `/Users/jtoper/DEV/triprank/DEPLOYMENT_TOPER_DEV.md`
- **K8s Manifests**: `/Users/jtoper/DEV/triprank/backend/k8s/`
- **Deploy Script**: `/Users/jtoper/DEV/triprank/deploy-to-toper.sh`

---

## 📞 Need Help?

1. Check logs: `kubectl logs -l app=fasttrack-api`
2. Check pod status: `kubectl get pods`
3. Check ingress: `kubectl describe ingress fasttrack-api`
4. Check certificate: `kubectl get certificate`
5. Test DNS: `nslookup fast.toper.dev`
6. Test endpoint: `curl -v https://fast.toper.dev/health`

---

**Domain**: fast.toper.dev  
**Server**: 10.0.0.102  
**Namespace**: default  
**Replicas**: 2  
**Resources**: 128Mi-512Mi RAM, 100m-1000m CPU

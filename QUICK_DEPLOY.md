# FastPass Deployment Quick Reference

## 🚀 Deploy to fast.toper.dev

### One-Line Deploy (Automated)
```bash
cd /Users/jtoper/DEV/triprank && ./deploy-to-toper.sh
```

### What It Does
1. ✅ Builds Docker image
2. ✅ Transfers to 10.0.0.102
3. ✅ Creates K8s secrets (JWT + DB)
4. ✅ Deploys 2 replicas
5. ✅ Configures nginx ingress
6. ✅ Requests SSL certificate
7. ✅ Tests health endpoint

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
host=postgres-service user=postgres password=YOUR_PASSWORD dbname=fastpass port=5432 sslmode=disable
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
ssh jtoper@10.0.0.102 "kubectl get pods -l app=fastpass-api"

# 2. Check logs
ssh jtoper@10.0.0.102 "kubectl logs -l app=fastpass-api --tail=50"

# 3. Test health
curl https://fast.toper.dev/health

# Expected: {"status":"ok"}
```

---

## 🔧 Common Commands

### View Logs (Live)
```bash
ssh jtoper@10.0.0.102 "kubectl logs -f deployment/fastpass-api"
```

### Restart Deployment
```bash
ssh jtoper@10.0.0.102 "kubectl rollout restart deployment/fastpass-api"
```

### Scale Replicas
```bash
ssh jtoper@10.0.0.102 "kubectl scale deployment fastpass-api --replicas=3"
```

### Check SSL Certificate
```bash
ssh jtoper@10.0.0.102 "kubectl get certificate fastpass-api-tls"
```

### Delete Everything
```bash
ssh jtoper@10.0.0.102 << 'EOF'
kubectl delete deployment fastpass-api
kubectl delete service fastpass-api
kubectl delete ingress fastpass-api
kubectl delete secret fastpass-secrets
EOF
```

---

## 🐛 Troubleshooting

### Pods Not Starting
```bash
# Check pod description
ssh jtoper@10.0.0.102 "kubectl describe pod -l app=fastpass-api"

# Check events
ssh jtoper@10.0.0.102 "kubectl get events --sort-by=.metadata.creationTimestamp"
```

### Database Connection Failed
```bash
# Test from within pod
ssh jtoper@10.0.0.102 "kubectl exec -it deployment/fastpass-api -- nc -zv postgres-service 5432"
```

### SSL Not Working
```bash
# Check certificate status
ssh jtoper@10.0.0.102 "kubectl describe certificate fastpass-api-tls"

# Check ingress
ssh jtoper@10.0.0.102 "kubectl describe ingress fastpass-api"
```

Wait 2-5 minutes for Let's Encrypt to issue certificate.

### Health Check Fails
```bash
# Test internally
ssh jtoper@10.0.0.102 "kubectl run test --rm -it --image=curlimages/curl -- curl http://fastpass-api/health"
```

---

## 📱 iOS App Configuration

After deployment, iOS app is already configured to use:

```swift
// File: ios/FastPass/FastPass/Services/APIService.swift
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
go build -o fastpass-api

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
ssh jtoper@10.0.0.102 "kubectl top pods -l app=fastpass-api"
```

### Pod Status
```bash
ssh jtoper@10.0.0.102 "kubectl get pods -l app=fastpass-api -w"
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

1. Check logs: `kubectl logs -l app=fastpass-api`
2. Check pod status: `kubectl get pods`
3. Check ingress: `kubectl describe ingress fastpass-api`
4. Check certificate: `kubectl get certificate`
5. Test DNS: `nslookup fast.toper.dev`
6. Test endpoint: `curl -v https://fast.toper.dev/health`

---

**Domain**: fast.toper.dev  
**Server**: 10.0.0.102  
**Namespace**: default  
**Replicas**: 2  
**Resources**: 128Mi-512Mi RAM, 100m-1000m CPU

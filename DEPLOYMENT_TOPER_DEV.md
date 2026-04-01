# Deployment Guide for toper.dev

This guide will help you deploy FastTrack to your Kubernetes cluster at toper.dev with the endpoint `fast.toper.dev`.

## Prerequisites

✅ Kubernetes cluster running at 10.0.0.102  
✅ nginx-ingress-controller installed  
✅ cert-manager installed (for SSL certificates)  
✅ PostgreSQL database available  
✅ Docker installed locally  
✅ SSH access to server  

## Quick Deployment

### Option 1: Automated Script

```bash
cd /Users/jtoper/DEV/triprank
./deploy-to-toper.sh
```

The script will:
- Build Docker image
- Transfer to server
- Create secrets
- Deploy to Kubernetes
- Test health endpoint

### Option 2: Manual Deployment

Follow these steps if you prefer manual control:

---

## Step 1: Build Docker Image

```bash
cd /Users/jtoper/DEV/triprank/backend
docker build -t fasttrack-api:latest .
```

---

## Step 2: Transfer Image to Server

Save and transfer the image:

```bash
# Save image
docker save fasttrack-api:latest | gzip > /tmp/fasttrack-api.tar.gz

# Transfer to server
scp /tmp/fasttrack-api.tar.gz jtoper@10.0.0.102:/tmp/

# Load on server
ssh jtoper@10.0.0.102 "docker load < /tmp/fasttrack-api.tar.gz"
```

---

## Step 3: Prepare Database

### Option A: Use Existing PostgreSQL

If you have PostgreSQL running in your cluster:

```bash
# Connect to your existing PostgreSQL
ssh jtoper@10.0.0.102
kubectl exec -it <postgres-pod-name> -- psql -U postgres

# Create database
CREATE DATABASE fasttrack;
\q
```

### Option B: Deploy New PostgreSQL

```bash
# Create PostgreSQL deployment
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        env:
        - name: POSTGRES_DB
          value: fasttrack
        - name: POSTGRES_USER
          value: postgres
        - name: POSTGRES_PASSWORD
          value: YOUR_SECURE_PASSWORD
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: postgres-storage
        persistentVolumeClaim:
          claimName: postgres-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
  type: ClusterIP
EOF
```

---

## Step 4: Create Kubernetes Secret

Generate JWT secret and create K8s secret:

```bash
# Generate JWT secret
JWT_SECRET=$(openssl rand -base64 32)
echo "Generated JWT Secret: $JWT_SECRET"

# Create secret on server
ssh jtoper@10.0.0.102 << 'EOF'
kubectl create secret generic fasttrack-secrets \
  --from-literal=database-url="host=postgres-service user=postgres password=YOUR_PASSWORD dbname=fasttrack port=5432 sslmode=disable" \
  --from-literal=jwt-secret="YOUR_JWT_SECRET_HERE"
EOF
```

**Important**: Replace `YOUR_PASSWORD` and `YOUR_JWT_SECRET_HERE` with your actual values.

---

## Step 5: Deploy to Kubernetes

```bash
# Copy K8s manifests to server
scp backend/k8s/*.yaml jtoper@10.0.0.102:/tmp/

# Apply manifests
ssh jtoper@10.0.0.102 << 'EOF'
kubectl apply -f /tmp/service.yaml
kubectl apply -f /tmp/deployment.yaml
kubectl apply -f /tmp/ingress.yaml
EOF
```

---

## Step 6: Configure DNS

Add DNS record for `fast.toper.dev`:

```
Type: A
Name: fast
Value: <your-cluster-ingress-ip>
TTL: 300
```

To find your ingress IP:

```bash
ssh jtoper@10.0.0.102 "kubectl get svc -n ingress-nginx"
# Look for the EXTERNAL-IP of ingress-nginx-controller
```

---

## Step 7: Verify Deployment

Check pods are running:

```bash
ssh jtoper@10.0.0.102 "kubectl get pods -l app=fasttrack-api"
```

Expected output:
```
NAME                            READY   STATUS    RESTARTS   AGE
fasttrack-api-xxxxxxxxxx-xxxxx   1/1     Running   0          1m
fasttrack-api-xxxxxxxxxx-xxxxx   1/1     Running   0          1m
```

Check logs:

```bash
ssh jtoper@10.0.0.102 "kubectl logs -l app=fasttrack-api --tail=50"
```

Test health endpoint:

```bash
curl https://fast.toper.dev/health
```

Expected response:
```json
{"status":"ok"}
```

---

## Step 8: Update iOS App

Update the API endpoint in your iOS app:

**File**: `ios/FastTrack/FastTrack/Services/APIService.swift`

Change line 5 from:
```swift
private let baseURL = "http://localhost:8080/api/v1"
```

To:
```swift
private let baseURL = "https://fast.toper.dev/api/v1"
```

---

## Troubleshooting

### Pods not starting

```bash
# Check pod status
ssh jtoper@10.0.0.102 "kubectl describe pod -l app=fasttrack-api"

# Check events
ssh jtoper@10.0.0.102 "kubectl get events --sort-by=.metadata.creationTimestamp"
```

### Database connection issues

```bash
# Test database connectivity from pod
ssh jtoper@10.0.0.102 "kubectl exec -it deployment/fasttrack-api -- sh"
# Inside pod:
nc -zv postgres-service 5432
```

### SSL certificate not working

```bash
# Check cert-manager
ssh jtoper@10.0.0.102 "kubectl get certificate"
ssh jtoper@10.0.0.102 "kubectl describe certificate fasttrack-api-tls"

# Check ingress
ssh jtoper@10.0.0.102 "kubectl describe ingress fasttrack-api"
```

Certificate may take 2-5 minutes to provision.

### Health check failing

```bash
# Check if service is accessible from within cluster
ssh jtoper@10.0.0.102 << 'EOF'
kubectl run test-pod --rm -it --image=curlimages/curl -- sh
# Inside pod:
curl http://fasttrack-api/health
EOF
```

---

## Useful Commands

### View logs
```bash
ssh jtoper@10.0.0.102 "kubectl logs -f deployment/fasttrack-api"
```

### Restart deployment
```bash
ssh jtoper@10.0.0.102 "kubectl rollout restart deployment/fasttrack-api"
```

### Scale replicas
```bash
ssh jtoper@10.0.0.102 "kubectl scale deployment fasttrack-api --replicas=3"
```

### Update image
```bash
# After rebuilding and transferring new image
ssh jtoper@10.0.0.102 "kubectl rollout restart deployment/fasttrack-api"
```

### Delete deployment
```bash
ssh jtoper@10.0.0.102 << 'EOF'
kubectl delete deployment fasttrack-api
kubectl delete service fasttrack-api
kubectl delete ingress fasttrack-api
kubectl delete secret fasttrack-secrets
EOF
```

---

## API Endpoints

Once deployed, your API will be available at:

- **Base URL**: `https://fast.toper.dev`
- **Health**: `https://fast.toper.dev/health`
- **Auth**: `https://fast.toper.dev/api/v1/auth/apple`
- **Drives**: `https://fast.toper.dev/api/v1/drives`

---

## Security Checklist

- ✅ PostgreSQL password is strong and unique
- ✅ JWT secret is randomly generated (32+ characters)
- ✅ SSL/TLS enabled via Let's Encrypt
- ✅ Database not exposed publicly
- ✅ CORS configured appropriately
- ✅ Secrets stored in Kubernetes secrets (not in code)

---

## Next Steps

1. ✅ Deploy backend to Kubernetes
2. ✅ Verify health endpoint responds
3. ✅ Update iOS app with production URL
4. ✅ Test authentication flow
5. ✅ Test drive recording and sync
6. ✅ Monitor logs for errors
7. ✅ Set up monitoring/alerting (optional)

---

## Support

If you encounter issues:

1. Check pod logs: `kubectl logs -l app=fasttrack-api`
2. Check pod status: `kubectl get pods`
3. Check ingress: `kubectl describe ingress fasttrack-api`
4. Check cert-manager: `kubectl get certificate`
5. Test DNS: `nslookup fast.toper.dev`
6. Test endpoint: `curl -v https://fast.toper.dev/health`

---

**Deployment Date**: April 1, 2026  
**API Version**: 1.0  
**Domain**: fast.toper.dev  
**Kubernetes Namespace**: default

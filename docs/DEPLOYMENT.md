# Deployment Guide

FastTrack runs on a single-node Kubernetes cluster at **10.0.0.102**, exposed at **fast.toper.dev**.

---

## Prerequisites

On the server:
- Docker
- kubectl (connected to your cluster)
- nginx-ingress-controller running
- cert-manager installed (for Let's Encrypt SSL)

---

## Initial Deploy

### On the server
```bash
git clone https://github.com/jxt1009/fasttrack.git
cd fasttrack
./deploy-local.sh
```

The script:
1. Checks Docker and kubectl
2. Deploys independent PostgreSQL (20GB data PVC + 10GB backup PVC, hostPath volumes at `/data/fasttrack/`)
3. Builds the Docker image locally
4. Creates K8s secrets (`fasttrack-secrets`, `fasttrack-postgres-secret`) — auto-generates JWT secret
5. Deploys 2 API replicas
6. Applies ingress for `fast.toper.dev`
7. Sets up the daily backup CronJob
8. Runs a health check

### Deploying from Mac (via SSH)
```bash
cd /Users/jtoper/DEV/fasttrack
./deploy-to-toper.sh
```

---

## DNS Configuration

After deploy, `fast.toper.dev` must point to the server's public IP (`73.158.156.201`).

**Cloudflare DNS — manual:**
1. Log in to Cloudflare → DNS for `toper.dev`
2. Add/update an A record: `fast` → `73.158.156.201`
3. Set proxy to "DNS only" (grey cloud) for initial testing

**Find ingress IP:**
```bash
kubectl get svc -n ingress-nginx
# EXTERNAL-IP of ingress-nginx-controller
```

**Verify propagation:**
```bash
dig +short fast.toper.dev  # should return 73.158.156.201
curl https://fast.toper.dev/health
```

### Automated DNS (ExternalDNS + Cloudflare)

For automatic DNS management whenever a new Ingress is created:

```bash
# Get API token from https://dash.cloudflare.com/profile/api-tokens
# Permissions: Zone → DNS → Edit, Zone → Zone → Read, Zone: toper.dev
kubectl create secret generic cloudflare-api-token \
  --from-literal=cloudflare_api_token='YOUR_TOKEN'
kubectl apply -f backend/k8s/external-dns-cloudflare.yaml
```

---

## SSL Certificate

cert-manager automatically provisions a Let's Encrypt certificate for `fast.toper.dev` when the Ingress is created.

```bash
# Check certificate status
kubectl get certificate fasttrack-api-tls
kubectl describe certificate fasttrack-api-tls

# If issuance fails (DNS not propagated yet), delete and let it recreate
kubectl delete certificate fasttrack-api-tls
```

Certificate typically takes 2–5 minutes after DNS propagates.

---

## Updating the Deployment

```bash
# On server
cd ~/fasttrack
git pull
./deploy-local.sh

# Or manually rebuild + restart
cd ~/fasttrack/backend
docker build -t fasttrack-api:latest .
kubectl rollout restart deployment/fasttrack-api
```

---

## Kubernetes Resources

```
Namespace: default

Deployments:
  fasttrack-api       (2 replicas, 128Mi–512Mi RAM, 100m–1000m CPU)
  fasttrack-postgres  (1 replica)

Services:
  fasttrack-api                (ClusterIP :80 → :8080)
  fasttrack-postgres-service   (ClusterIP :5432)

Ingress:
  fasttrack-api  →  fast.toper.dev  (TLS via cert-manager)

CronJob:
  fasttrack-postgres-backup  (daily at 2 AM UTC)

Secrets:
  fasttrack-secrets          (database-url, jwt-secret)
  fasttrack-postgres-secret  (postgres-password)

PVCs (hostPath):
  fasttrack-postgres-pvc         20GB  →  /data/fasttrack/postgres
  fasttrack-postgres-backup-pvc  10GB  →  /data/fasttrack/backups
```

---

## Managing the Deployment

### View logs
```bash
kubectl logs -f deployment/fasttrack-api
kubectl logs -f deployment/fasttrack-postgres
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller | grep fast.toper.dev
```

### Restart / scale
```bash
kubectl rollout restart deployment/fasttrack-api
kubectl scale deployment fasttrack-api --replicas=3
```

### Check status
```bash
kubectl get pods -l app=fasttrack-api
kubectl get pods -l app=fasttrack-postgres
kubectl get ingress fasttrack-api
kubectl get certificate fasttrack-api-tls
kubectl get pvc | grep fasttrack
```

### Resource usage
```bash
kubectl top pods
kubectl top nodes
```

### Rotate secrets
```bash
NEW_JWT=$(openssl rand -base64 32)
kubectl delete secret fasttrack-secrets
kubectl create secret generic fasttrack-secrets \
  --from-literal=database-url="host=fasttrack-postgres-service user=fasttrack password=<DB_PASS> dbname=fasttrack port=5432 sslmode=disable" \
  --from-literal=jwt-secret="$NEW_JWT"
kubectl rollout restart deployment/fasttrack-api
```

---

## Teardown

```bash
kubectl delete deployment fasttrack-api fasttrack-postgres
kubectl delete svc fasttrack-api fasttrack-postgres-service
kubectl delete ingress fasttrack-api
kubectl delete secret fasttrack-secrets fasttrack-postgres-secret
kubectl delete pvc fasttrack-postgres-pvc fasttrack-postgres-backup-pvc
kubectl delete cronjob fasttrack-postgres-backup
```

---

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod -l app=fasttrack-api
kubectl get events --sort-by=.metadata.creationTimestamp
```

Common causes: missing secret, image not found locally, insufficient resources.

### Database connection refused
```bash
# Check postgres pod
kubectl get pods -l app=fasttrack-postgres
kubectl logs -l app=fasttrack-postgres

# Verify password matches in both secrets
kubectl get secret fasttrack-postgres-secret -o jsonpath='{.data.postgres-password}' | base64 -d
kubectl get secret fasttrack-secrets -o jsonpath='{.data.database-url}' | base64 -d

# Test from within cluster
kubectl run test-db --rm -it --image=postgres:15-alpine --restart=Never -- \
  psql -h fasttrack-postgres-service -U fasttrack -d fasttrack
```

### PVC not bound (storage class issue)
```bash
kubectl get storageclass
# Edit backend/k8s/postgres-hostpath.yaml to use the correct storageClassName
kubectl apply -f backend/k8s/postgres-hostpath.yaml
```

### SSL not working
```bash
kubectl describe certificate fasttrack-api-tls
kubectl logs -n cert-manager deployment/cert-manager
```

Ensure DNS is propagated before Let's Encrypt can issue the cert. Ports 80 and 443 must be reachable.

### Health check fails externally
```bash
# Test from inside cluster
kubectl run test --rm -it --image=curlimages/curl --restart=Never -- \
  curl http://fasttrack-api/health

# Check ingress
kubectl describe ingress fasttrack-api

# Check nginx logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller | grep fast.toper.dev
```

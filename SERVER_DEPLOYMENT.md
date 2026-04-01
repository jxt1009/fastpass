# Server Deployment Guide

## Prerequisites on Server

- Go 1.26+
- PostgreSQL database
- Kubernetes cluster with kubectl access
- Docker (for building images)

## Quick Deploy to Kubernetes

### 1. Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/fastpass.git
cd fastpass
```

### 2. Build Docker Image

```bash
cd backend
docker build -t your-registry/fastpass-api:latest .
docker push your-registry/fastpass-api:latest
```

### 3. Configure Kubernetes

```bash
cd k8s

# Copy and edit secret
cp secret.yaml.example secret.yaml
# Edit secret.yaml with your database credentials and JWT secret

# Update deployment.yaml with your Docker image
# Update ingress.yaml with your domain

# Apply to cluster
kubectl apply -f secret.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml
```

### 4. Verify Deployment

```bash
# Check pods are running
kubectl get pods -l app=triprank-api

# Check logs
kubectl logs -l app=triprank-api

# Check ingress
kubectl get ingress triprank-api

# Test health endpoint
curl https://your-domain.com/health
```

## Environment Variables

Set these in Kubernetes secret or deployment:

- `DATABASE_URL` - PostgreSQL connection string
- `JWT_SECRET` - Secure random string for JWT signing
- `PORT` - API port (default: 8080)

### Generate JWT Secret

```bash
openssl rand -base64 32
```

## Database Setup

The backend will auto-create tables on first run:
- `users` - User accounts from Apple Sign In
- `drives` - Trip data with user relationships

## Local Testing (No Kubernetes)

```bash
# Install PostgreSQL
# Create database
createdb fastpass

# Set environment
export DATABASE_URL="host=localhost user=postgres password=postgres dbname=fastpass port=5432 sslmode=disable"
export JWT_SECRET="your-secret-here"

# Run
cd backend
go build -o fastpass-api
./fastpass-api
```

## iOS App Configuration

Before deploying, update the backend URL in iOS app:

```swift
// ios/FastPass/FastPass/Services/APIService.swift
private let baseURL = "https://your-domain.com/api/v1"
```

Then rebuild and deploy to TestFlight or App Store.

## Monitoring

```bash
# Watch logs in real-time
kubectl logs -f -l app=triprank-api

# Check pod status
kubectl describe pod -l app=triprank-api

# View service
kubectl get svc triprank-api
```

## Troubleshooting

### Database Connection Issues
```bash
# Verify secret
kubectl get secret triprank-secrets -o yaml

# Check DATABASE_URL format
# Should be: host=HOST user=USER password=PASS dbname=DB port=5432 sslmode=require
```

### 502 Bad Gateway
- Check pods are running: `kubectl get pods`
- Check logs for errors: `kubectl logs -l app=triprank-api`
- Verify service endpoints: `kubectl get endpoints triprank-api`

### Authentication Failing
- Verify JWT_SECRET is set
- Check Apple Sign In token verification
- Ensure HTTPS is working (required for Apple Sign In)

## Scaling

Scale up replicas:
```bash
kubectl scale deployment triprank-api --replicas=3
```

Update deployment:
```bash
kubectl set image deployment/triprank-api triprank-api=your-registry/fastpass-api:v2
```

## Rollback

```bash
kubectl rollout undo deployment/triprank-api
```

---

**Support**: See backend/DEPLOYMENT.md for detailed Kubernetes configuration

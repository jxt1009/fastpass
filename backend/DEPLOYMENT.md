# Kubernetes Deployment

## Prerequisites

1. PostgreSQL database running in cluster
2. Ingress controller (nginx) configured
3. cert-manager for TLS certificates

## Setup

1. Create secret with database credentials:
```bash
cp k8s/secret.yaml.example k8s/secret.yaml
# Edit secret.yaml with your database credentials
kubectl apply -f k8s/secret.yaml
```

2. Build and push Docker image:
```bash
docker build -t your-registry/triprank-api:latest .
docker push your-registry/triprank-api:latest
```

3. Update image in k8s/deployment.yaml with your registry URL

4. Deploy to Kubernetes:
```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
```

5. Update ingress host in k8s/ingress.yaml with your domain

## Verify deployment

```bash
kubectl get pods -l app=triprank-api
kubectl logs -l app=triprank-api
kubectl get ingress triprank-api
```

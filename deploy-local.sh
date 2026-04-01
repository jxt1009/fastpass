#!/bin/bash

set -e

echo "🚀 FastPass Local Deployment Script"
echo "===================================="
echo "Running on: $(hostname)"
echo "User: $(whoami)"
echo ""

# Configuration
NAMESPACE="default"
APP_NAME="fastpass-api"
DOMAIN="fast.toper.dev"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="${SCRIPT_DIR}/backend"
K8S_DIR="${BACKEND_DIR}/k8s"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if running on server
echo -e "${BLUE}→ Checking environment...${NC}"
if [ ! -d "$BACKEND_DIR" ]; then
    echo -e "${RED}✗ Backend directory not found: $BACKEND_DIR${NC}"
    echo "  Please run this script from the FastPass repository root"
    exit 1
fi
echo -e "${GREEN}✓ Repository found${NC}"
echo ""

# Check if Docker is available
echo -e "${BLUE}→ Checking Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found${NC}"
    echo "  Install with: curl -fsSL https://get.docker.com | sh"
    exit 1
fi
echo -e "${GREEN}✓ Docker is available${NC}"
echo ""

# Check if kubectl is available
echo -e "${BLUE}→ Checking kubectl...${NC}"
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found${NC}"
    echo "  Install kubectl to continue"
    exit 1
fi
echo -e "${GREEN}✓ kubectl is available${NC}"
echo ""

# Check if PostgreSQL is available
echo -e "${BLUE}→ Checking PostgreSQL availability...${NC}"
if kubectl get svc -n $NAMESPACE fastpass-postgres-service &>/dev/null; then
    echo -e "${GREEN}✓ FastPass PostgreSQL service found${NC}"
    POSTGRES_SERVICE="fastpass-postgres-service"
    POSTGRES_USER="fastpass"
else
    echo -e "${YELLOW}⚠ FastPass PostgreSQL not found${NC}"
    echo ""
    echo "FastPass needs its own PostgreSQL database (independent from other services)."
    echo "Would you like to deploy PostgreSQL for FastPass now? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}→ Deploying PostgreSQL for FastPass...${NC}"
        
        # Generate random password
        PG_PASSWORD=$(openssl rand -base64 24)
        
        # Create postgres secret
        kubectl create secret generic fastpass-postgres-secret -n $NAMESPACE \
            --from-literal=postgres-password="$PG_PASSWORD" \
            --dry-run=client -o yaml | kubectl apply -f -
        
        # Deploy postgres
        kubectl apply -f "$K8S_DIR/postgres.yaml"
        
        echo -e "${GREEN}✓ PostgreSQL deployed${NC}"
        echo -e "${YELLOW}  Database: fastpass${NC}"
        echo -e "${YELLOW}  User: fastpass${NC}"
        echo -e "${YELLOW}  Password: $PG_PASSWORD${NC}"
        echo -e "${YELLOW}  (Save this password securely!)${NC}"
        
        POSTGRES_SERVICE="fastpass-postgres-service"
        POSTGRES_USER="fastpass"
        DB_PASSWORD="$PG_PASSWORD"
        
        # Wait for postgres to be ready
        echo -e "${BLUE}→ Waiting for PostgreSQL to be ready...${NC}"
        kubectl wait --for=condition=ready pod -l app=fastpass-postgres -n $NAMESPACE --timeout=180s
        echo -e "${GREEN}✓ PostgreSQL is ready${NC}"
        
        # Deploy backup CronJob
        echo -e "${BLUE}→ Setting up automated backups...${NC}"
        kubectl apply -f "$K8S_DIR/backup-cronjob.yaml"
        echo -e "${GREEN}✓ Backup CronJob configured (runs daily at 2 AM)${NC}"
    else
        echo -e "${RED}✗ PostgreSQL is required for FastPass${NC}"
        echo "  Deploy it manually or re-run this script"
        exit 1
    fi
fi
echo ""

# Step 1: Build Docker image
echo -e "${BLUE}→ Building Docker image...${NC}"
cd "$BACKEND_DIR"
if docker build -t $APP_NAME:latest .; then
    echo -e "${GREEN}✓ Docker image built successfully${NC}"
else
    echo -e "${RED}✗ Docker build failed${NC}"
    exit 1
fi
cd "$SCRIPT_DIR"
echo ""

# Step 2: Create or update secret
echo -e "${BLUE}→ Checking for Kubernetes secrets...${NC}"
if kubectl get secret fastpass-secrets -n $NAMESPACE &>/dev/null; then
    echo -e "${YELLOW}⚠ Secret already exists${NC}"
    echo "Update secret? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Enter PostgreSQL password (press Enter to keep existing):"
        read -r db_password
        
        echo "Enter JWT secret (press Enter to generate new):"
        read -r jwt_secret
        
        if [ -z "$jwt_secret" ]; then
            jwt_secret=$(openssl rand -base64 32)
            echo -e "${GREEN}✓ Generated new JWT secret${NC}"
        fi
        
        if [ ! -z "$db_password" ]; then
            DB_PASSWORD="$db_password"
        fi
        
        if [ ! -z "$DB_PASSWORD" ]; then
            kubectl delete secret fastpass-secrets -n $NAMESPACE
            kubectl create secret generic fastpass-secrets -n $NAMESPACE \
                --from-literal=database-url="host=${POSTGRES_SERVICE:-postgres-service} user=postgres password=$DB_PASSWORD dbname=fastpass port=5432 sslmode=disable" \
                --from-literal=jwt-secret="$jwt_secret"
            echo -e "${GREEN}✓ Secret updated${NC}"
        else
            echo -e "${YELLOW}⚠ Keeping existing secret${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠ Secret not found. Creating...${NC}"
    
    if [ -z "$DB_PASSWORD" ]; then
        echo "Enter PostgreSQL password:"
        read -s db_password
        echo ""
        DB_PASSWORD="$db_password"
    fi
    
    jwt_secret=$(openssl rand -base64 32)
    echo -e "${GREEN}✓ Generated JWT secret${NC}"
    
    POSTGRES_USER="${POSTGRES_USER:-fastpass}"
    POSTGRES_SERVICE="${POSTGRES_SERVICE:-fastpass-postgres-service}"
    
    kubectl create secret generic fastpass-secrets -n $NAMESPACE \
        --from-literal=database-url="host=$POSTGRES_SERVICE user=$POSTGRES_USER password=$DB_PASSWORD dbname=fastpass port=5432 sslmode=disable" \
        --from-literal=jwt-secret="$jwt_secret"
    echo -e "${GREEN}✓ Secret created${NC}"
    echo -e "${YELLOW}  JWT Secret: $jwt_secret${NC}"
    echo -e "${YELLOW}  (Save this for your records)${NC}"
fi
echo ""

# Step 3: Deploy to Kubernetes
echo -e "${BLUE}→ Deploying to Kubernetes...${NC}"

# Apply manifests
kubectl apply -f "$K8S_DIR/service.yaml"
kubectl apply -f "$K8S_DIR/deployment.yaml"
kubectl apply -f "$K8S_DIR/ingress.yaml"

echo -e "${GREEN}✓ Kubernetes manifests applied${NC}"
echo ""

# Step 4: Wait for deployment
echo -e "${BLUE}→ Waiting for deployment to be ready...${NC}"
if kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s; then
    echo -e "${GREEN}✓ Deployment ready!${NC}"
else
    echo -e "${RED}✗ Deployment failed to become ready${NC}"
    echo "Check logs with: kubectl logs -l app=$APP_NAME -n $NAMESPACE"
    exit 1
fi
echo ""

# Step 5: Show status
echo -e "${BLUE}→ Deployment Status:${NC}"
kubectl get pods -n $NAMESPACE -l app=$APP_NAME
echo ""

# Step 6: Show service info
echo -e "${BLUE}→ Service Information:${NC}"
kubectl get svc -n $NAMESPACE $APP_NAME
echo ""

# Step 7: Show ingress info
echo -e "${BLUE}→ Ingress Information:${NC}"
kubectl get ingress -n $NAMESPACE $APP_NAME
echo ""

# Step 8: Test health endpoint
echo -e "${BLUE}→ Testing health endpoint...${NC}"
echo "Waiting 10 seconds for services to stabilize..."
sleep 10

# Try internal health check first
if kubectl run test-curl --rm -i --image=curlimages/curl --restart=Never -- curl -sSf http://$APP_NAME/health &>/dev/null; then
    echo -e "${GREEN}✓ Internal health check passed${NC}"
else
    echo -e "${YELLOW}⚠ Internal health check pending${NC}"
fi

# Try external health check
if curl -sSf https://$DOMAIN/health &>/dev/null; then
    echo -e "${GREEN}✓ External health check passed!${NC}"
    echo -e "${GREEN}✓ API is live at: https://$DOMAIN${NC}"
else
    echo -e "${YELLOW}⚠ External health check pending${NC}"
    echo "  This is normal if DNS/SSL is still propagating"
    echo "  Try manually: curl https://$DOMAIN/health"
fi
echo ""

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}🎉 Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "API Endpoint: ${BLUE}https://$DOMAIN${NC}"
echo -e "Health Check: ${BLUE}https://$DOMAIN/health${NC}"
echo ""
echo "Useful commands:"
echo "  View logs:    kubectl logs -f -l app=$APP_NAME -n $NAMESPACE"
echo "  View pods:    kubectl get pods -l app=$APP_NAME -n $NAMESPACE"
echo "  Restart:      kubectl rollout restart deployment/$APP_NAME -n $NAMESPACE"
echo "  Scale:        kubectl scale deployment/$APP_NAME --replicas=3 -n $NAMESPACE"
echo ""
echo "Check SSL certificate:"
echo "  kubectl get certificate -n $NAMESPACE"
echo "  kubectl describe certificate fastpass-api-tls -n $NAMESPACE"
echo ""
echo "Next steps:"
echo "  1. Configure DNS for $DOMAIN to point to your ingress IP"
echo "  2. Wait for Let's Encrypt certificate (2-5 minutes)"
echo "  3. Test with: curl https://$DOMAIN/health"
echo "  4. iOS app is already configured to use https://$DOMAIN/api/v1"
echo ""

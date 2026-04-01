#!/bin/bash

set -e

echo "🚀 FastPass Deployment to toper.dev"
echo "===================================="
echo ""

# Configuration
SERVER="jtoper@10.0.0.102"
NAMESPACE="default"
APP_NAME="fastpass-api"
DOMAIN="fast.toper.dev"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if we can connect to server
echo -e "${BLUE}→ Checking server connection...${NC}"
if ! ssh -o ConnectTimeout=5 $SERVER "echo 'Connected'" 2>/dev/null; then
    echo -e "${RED}✗ Cannot connect to server at $SERVER${NC}"
    echo "  Please check:"
    echo "    - Server is running"
    echo "    - You have SSH access"
    echo "    - Network connectivity"
    exit 1
fi
echo -e "${GREEN}✓ Server connection successful${NC}"
echo ""

# Step 1: Check if PostgreSQL is available
echo -e "${BLUE}→ Checking PostgreSQL availability...${NC}"
if ssh $SERVER "kubectl get svc -n $NAMESPACE | grep -q postgres"; then
    echo -e "${GREEN}✓ PostgreSQL service found${NC}"
else
    echo -e "${YELLOW}⚠ PostgreSQL service not found in namespace $NAMESPACE${NC}"
    echo "  You may need to deploy PostgreSQL first"
    echo "  Continue anyway? (y/n)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
echo ""

# Step 2: Build Docker image
echo -e "${BLUE}→ Building Docker image...${NC}"
cd backend
if docker build -t $APP_NAME:latest .; then
    echo -e "${GREEN}✓ Docker image built successfully${NC}"
else
    echo -e "${RED}✗ Docker build failed${NC}"
    exit 1
fi
cd ..
echo ""

# Step 3: Save and transfer image
echo -e "${BLUE}→ Saving Docker image...${NC}"
docker save $APP_NAME:latest | gzip > /tmp/${APP_NAME}.tar.gz
echo -e "${GREEN}✓ Image saved to /tmp/${APP_NAME}.tar.gz${NC}"
echo ""

echo -e "${BLUE}→ Transferring image to server...${NC}"
scp /tmp/${APP_NAME}.tar.gz $SERVER:/tmp/
echo -e "${GREEN}✓ Image transferred${NC}"
echo ""

# Step 4: Load image on server
echo -e "${BLUE}→ Loading image on server...${NC}"
ssh $SERVER "docker load < /tmp/${APP_NAME}.tar.gz && rm /tmp/${APP_NAME}.tar.gz"
echo -e "${GREEN}✓ Image loaded on server${NC}"
echo ""

# Clean up local image
rm /tmp/${APP_NAME}.tar.gz

# Step 5: Create secret if it doesn't exist
echo -e "${BLUE}→ Checking for secrets...${NC}"
if ssh $SERVER "kubectl get secret fastpass-secrets -n $NAMESPACE" 2>/dev/null; then
    echo -e "${YELLOW}⚠ Secret already exists. Update it? (y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Enter PostgreSQL connection string (or press Enter to skip):"
        read -r db_url
        
        echo "Enter JWT secret (or press Enter to generate):"
        read -r jwt_secret
        
        if [ -z "$jwt_secret" ]; then
            jwt_secret=$(openssl rand -base64 32)
            echo -e "${GREEN}✓ Generated JWT secret${NC}"
        fi
        
        if [ ! -z "$db_url" ]; then
            ssh $SERVER "kubectl delete secret fastpass-secrets -n $NAMESPACE"
            ssh $SERVER "kubectl create secret generic fastpass-secrets -n $NAMESPACE \
                --from-literal=database-url='$db_url' \
                --from-literal=jwt-secret='$jwt_secret'"
            echo -e "${GREEN}✓ Secret updated${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠ Secret not found. Creating...${NC}"
    echo "Enter PostgreSQL connection string:"
    echo "Format: host=HOSTNAME user=USERNAME password=PASSWORD dbname=fastpass port=5432 sslmode=disable"
    read -r db_url
    
    jwt_secret=$(openssl rand -base64 32)
    echo -e "${GREEN}✓ Generated JWT secret: $jwt_secret${NC}"
    
    ssh $SERVER "kubectl create secret generic fastpass-secrets -n $NAMESPACE \
        --from-literal=database-url='$db_url' \
        --from-literal=jwt-secret='$jwt_secret'"
    echo -e "${GREEN}✓ Secret created${NC}"
fi
echo ""

# Step 6: Deploy to Kubernetes
echo -e "${BLUE}→ Deploying to Kubernetes...${NC}"

# Copy K8s manifests to server
scp backend/k8s/*.yaml $SERVER:/tmp/

# Apply manifests
ssh $SERVER "kubectl apply -f /tmp/service.yaml"
ssh $SERVER "kubectl apply -f /tmp/deployment.yaml"
ssh $SERVER "kubectl apply -f /tmp/ingress.yaml"

# Clean up
ssh $SERVER "rm /tmp/*.yaml"

echo -e "${GREEN}✓ Kubernetes manifests applied${NC}"
echo ""

# Step 7: Wait for deployment
echo -e "${BLUE}→ Waiting for deployment to be ready...${NC}"
ssh $SERVER "kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s"
echo -e "${GREEN}✓ Deployment ready!${NC}"
echo ""

# Step 8: Show status
echo -e "${BLUE}→ Deployment Status:${NC}"
ssh $SERVER "kubectl get pods -n $NAMESPACE -l app=$APP_NAME"
echo ""

# Step 9: Test health endpoint
echo -e "${BLUE}→ Testing health endpoint...${NC}"
sleep 5
if curl -sSf https://$DOMAIN/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Health check passed!${NC}"
    echo -e "${GREEN}✓ API is live at: https://$DOMAIN${NC}"
else
    echo -e "${YELLOW}⚠ Health check pending (may take a few minutes for DNS/cert)${NC}"
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
echo "  View logs:    ssh $SERVER 'kubectl logs -f -l app=$APP_NAME -n $NAMESPACE'"
echo "  View pods:    ssh $SERVER 'kubectl get pods -l app=$APP_NAME -n $NAMESPACE'"
echo "  Restart:      ssh $SERVER 'kubectl rollout restart deployment/$APP_NAME -n $NAMESPACE'"
echo "  Delete:       ssh $SERVER 'kubectl delete -f /path/to/manifests'"
echo ""
echo "Next steps:"
echo "  1. Update iOS app APIService.swift with: https://$DOMAIN"
echo "  2. Configure DNS for $DOMAIN to point to your cluster"
echo "  3. Wait for Let's Encrypt certificate (may take a few minutes)"
echo ""

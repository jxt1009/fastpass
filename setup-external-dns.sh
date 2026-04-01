#!/bin/bash
set -e

echo "=========================================="
echo "ExternalDNS Setup for Cloudflare"
echo "=========================================="
echo ""

# Check if running on server
if [ ! -f /etc/kubernetes/admin.conf ] && [ ! -f ~/.kube/config ]; then
    echo "❌ Error: kubectl not configured"
    echo "Please run this script on your Kubernetes server or configure kubectl"
    exit 1
fi

# Check for API token
if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo "❌ Error: CLOUDFLARE_API_TOKEN not set"
    echo ""
    echo "To get a Cloudflare API token:"
    echo "1. Go to https://dash.cloudflare.com/profile/api-tokens"
    echo "2. Click 'Create Token'"
    echo "3. Use template: 'Edit zone DNS'"
    echo "4. Set permissions:"
    echo "   - Zone → DNS → Edit"
    echo "   - Zone → Zone → Read"
    echo "5. Zone Resources: Include → Specific zone → toper.dev"
    echo "6. Copy the token and run:"
    echo ""
    echo "   export CLOUDFLARE_API_TOKEN='your_token_here'"
    echo "   bash $0"
    echo ""
    exit 1
fi

echo "✅ Cloudflare API token found"
echo ""

# Create secret
echo "📝 Creating Kubernetes secret..."
kubectl create secret generic cloudflare-api-token \
  --from-literal=cloudflare_api_token="$CLOUDFLARE_API_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Secret created"
echo ""

# Find script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Deploy ExternalDNS
if [ -f "$SCRIPT_DIR/backend/k8s/external-dns-cloudflare.yaml" ]; then
    YAML_FILE="$SCRIPT_DIR/backend/k8s/external-dns-cloudflare.yaml"
elif [ -f "$SCRIPT_DIR/k8s/external-dns-cloudflare.yaml" ]; then
    YAML_FILE="$SCRIPT_DIR/k8s/external-dns-cloudflare.yaml"
elif [ -f "$SCRIPT_DIR/../k8s/external-dns-cloudflare.yaml" ]; then
    YAML_FILE="$SCRIPT_DIR/../k8s/external-dns-cloudflare.yaml"
else
    echo "❌ Error: Could not find external-dns-cloudflare.yaml"
    echo "Looking in:"
    echo "  - $SCRIPT_DIR/backend/k8s/external-dns-cloudflare.yaml"
    echo "  - $SCRIPT_DIR/k8s/external-dns-cloudflare.yaml"
    exit 1
fi

echo "📝 Deploying ExternalDNS from $YAML_FILE..."
kubectl apply -f "$YAML_FILE"

echo "✅ ExternalDNS deployed!"
echo ""

# Wait for pod to be ready
echo "⏳ Waiting for ExternalDNS pod to be ready..."
kubectl wait --for=condition=ready pod -l app=external-dns --timeout=60s || true

echo ""
echo "=========================================="
echo "✅ Setup Complete!"
echo "=========================================="
echo ""
echo "ExternalDNS will now automatically manage DNS records for your ingresses."
echo ""
echo "📊 Check status:"
echo "   kubectl get pods -l app=external-dns"
echo ""
echo "📋 View logs:"
echo "   kubectl logs -l app=external-dns -f"
echo ""
echo "🔍 Check your Cloudflare DNS records:"
echo "   https://dash.cloudflare.com/"
echo ""
echo "DNS records should appear within 1-2 minutes."
echo "You should see:"
echo "  - A record: fast.toper.dev → 73.158.156.201"
echo "  - TXT record: _external-dns.fast.toper.dev (for ownership)"
echo ""
echo "🧪 Test your API:"
echo "   curl https://fast.toper.dev/health"
echo "   # Expected: {\"status\":\"ok\"}"
echo ""

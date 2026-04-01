# Automated DNS Configuration for Kubernetes

This guide shows how to automatically manage DNS records for your Kubernetes ingresses using Cloudflare.

## Option 1: ExternalDNS (Recommended for Multiple Services)

ExternalDNS automatically creates/updates DNS records based on your Ingress resources.

### Benefits:
- ✅ Automatic DNS record creation for any new Ingress
- ✅ Automatic cleanup when Ingress is deleted
- ✅ Works with Cloudflare, Route53, Google Cloud DNS, etc.
- ✅ No manual DNS changes needed

### Setup Steps:

#### 1. Get Cloudflare API Token

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Go to **My Profile** → **API Tokens**
3. Click **Create Token**
4. Use template: **Edit zone DNS**
5. Permissions:
   - Zone → DNS → Edit
   - Zone → Zone → Read
6. Zone Resources:
   - Include → Specific zone → `toper.dev`
7. Copy the API token (only shown once!)

#### 2. Create Secret for API Token

```bash
kubectl create secret generic cloudflare-api-token \
  --from-literal=cloudflare_api_token='YOUR_TOKEN_HERE'
```

#### 3. Deploy ExternalDNS

```bash
kubectl apply -f k8s/external-dns-cloudflare.yaml
```

#### 4. Update Your Ingress (Already Done!)

Your ingress already has the right hostname (`fast.toper.dev`). ExternalDNS will automatically:
- Detect the hostname
- Get the ingress IP (10.0.0.102 or LoadBalancer IP)
- Create/update A record in Cloudflare

### Configuration File

Create `backend/k8s/external-dns-cloudflare.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-dns
rules:
- apiGroups: [""]
  resources: ["services","endpoints","pods"]
  verbs: ["get","watch","list"]
- apiGroups: ["extensions","networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get","watch","list"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["list","watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
- kind: ServiceAccount
  name: external-dns
  namespace: default
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
  namespace: default
spec:
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: external-dns
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
      - name: external-dns
        image: registry.k8s.io/external-dns/external-dns:v0.14.0
        args:
        - --source=ingress
        - --domain-filter=toper.dev  # Only manage toper.dev records
        - --provider=cloudflare
        - --cloudflare-proxied  # Enable Cloudflare proxy (orange cloud)
        - --log-level=info
        env:
        - name: CF_API_TOKEN
          valueFrom:
            secretKeyRef:
              name: cloudflare-api-token
              key: cloudflare_api_token
```

**Note**: Remove `--cloudflare-proxied` if you want direct connection (grey cloud) instead of through Cloudflare's proxy.

---

## Option 2: Cloudflare Tunnel (Best for Home Servers)

Cloudflare Tunnel creates a secure outbound connection without exposing your IP.

### Benefits:
- ✅ No port forwarding needed
- ✅ No public IP exposure
- ✅ Built-in DDoS protection
- ✅ Free for personal use
- ✅ Works behind NAT/firewall

### Setup Steps:

#### 1. Install cloudflared on Server

```bash
# Download and install
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb

# Or use Docker (recommended for K8s)
```

#### 2. Authenticate with Cloudflare

```bash
cloudflared tunnel login
```

This opens a browser to authenticate and downloads a cert to `~/.cloudflared/cert.pem`.

#### 3. Create Tunnel

```bash
cloudflared tunnel create fasttrack-tunnel
# Note the tunnel ID shown
```

#### 4. Configure Tunnel

Create `~/.cloudflared/config.yml`:

```yaml
tunnel: YOUR_TUNNEL_ID
credentials-file: /root/.cloudflared/YOUR_TUNNEL_ID.json

ingress:
  - hostname: fast.toper.dev
    service: http://fasttrack-api.default.svc.cluster.local:80
  - hostname: "*.toper.dev"
    service: http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80
  - service: http_status:404
```

#### 5. Create DNS Record (One Time)

```bash
cloudflared tunnel route dns fasttrack-tunnel fast.toper.dev
```

#### 6. Run Tunnel in Kubernetes

Create `backend/k8s/cloudflare-tunnel.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: tunnel-credentials
  namespace: default
type: Opaque
stringData:
  credentials.json: |
    {
      "AccountTag": "YOUR_ACCOUNT_ID",
      "TunnelSecret": "YOUR_TUNNEL_SECRET",
      "TunnelID": "YOUR_TUNNEL_ID"
    }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloudflared
  namespace: default
data:
  config.yaml: |
    tunnel: YOUR_TUNNEL_ID
    credentials-file: /etc/cloudflared/credentials.json
    metrics: 0.0.0.0:2000
    no-autoupdate: true
    ingress:
      - hostname: fast.toper.dev
        service: http://fasttrack-api:80
      - service: http_status:404
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cloudflared
  template:
    metadata:
      labels:
        app: cloudflared
    spec:
      containers:
      - name: cloudflared
        image: cloudflare/cloudflared:latest
        args:
        - tunnel
        - --config
        - /etc/cloudflared/config.yaml
        - run
        livenessProbe:
          httpGet:
            path: /ready
            port: 2000
          failureThreshold: 1
          initialDelaySeconds: 10
          periodSeconds: 10
        volumeMounts:
        - name: config
          mountPath: /etc/cloudflared
          readOnly: true
        - name: creds
          mountPath: /etc/cloudflared/credentials.json
          subPath: credentials.json
          readOnly: true
      volumes:
      - name: config
        configMap:
          name: cloudflared
      - name: creds
        secret:
          secretName: tunnel-credentials
```

Then deploy:

```bash
kubectl apply -f backend/k8s/cloudflare-tunnel.yaml
```

---

## Comparison

| Feature | ExternalDNS | Cloudflare Tunnel |
|---------|-------------|-------------------|
| Setup Complexity | Medium | Medium |
| Multiple Services | Automatic | Manual config |
| Port Forwarding | Required | Not required |
| IP Exposure | Yes (or LoadBalancer) | No |
| DDoS Protection | Optional (via CF proxy) | Built-in |
| Works Behind NAT | No (needs LoadBalancer) | Yes |
| Best For | Cloud/VPS with public IP | Home servers |

---

## Quick Setup for Your Server

Since you have a public IP (73.158.156.201) and nginx-ingress already, **ExternalDNS is the simplest**:

### Quick Install Script

Create `setup-external-dns.sh`:

```bash
#!/bin/bash
set -e

echo "Setting up ExternalDNS for Cloudflare..."

# Check for API token
if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo "Error: Please set CLOUDFLARE_API_TOKEN environment variable"
    echo "Get one from: https://dash.cloudflare.com/profile/api-tokens"
    exit 1
fi

# Create secret
kubectl create secret generic cloudflare-api-token \
  --from-literal=cloudflare_api_token="$CLOUDFLARE_API_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

# Deploy ExternalDNS
kubectl apply -f backend/k8s/external-dns-cloudflare.yaml

echo "✅ ExternalDNS deployed!"
echo ""
echo "It will automatically create DNS records for all ingresses."
echo "Check logs: kubectl logs -l app=external-dns -f"
echo ""
echo "Your fast.toper.dev DNS record should be created in ~1 minute."
```

Usage:

```bash
export CLOUDFLARE_API_TOKEN="your_token_here"
bash setup-external-dns.sh
```

---

## Current Manual Setup (What You Have Now)

For now, you need to:

1. Log in to Cloudflare
2. Go to DNS settings for `toper.dev`
3. Add/Update A record:
   - Name: `fast`
   - Type: A
   - IPv4 address: `73.158.156.201`
   - TTL: Auto
   - Proxy status: Proxied (orange cloud) or DNS only (grey cloud)

**Recommendation**: Set to "DNS only" (grey cloud) initially for easier debugging, then enable proxy later for DDoS protection.

---

## Future Improvements

Once ExternalDNS is set up, you can:

1. **Add new services** - Just create an Ingress, DNS is automatic
2. **Wildcard support** - Use `*.toper.dev` for dynamic subdomains
3. **Multiple environments** - e.g., `dev.toper.dev`, `staging.toper.dev`, `prod.toper.dev`
4. **LoadBalancer services** - ExternalDNS can also watch Services with type=LoadBalancer

---

## Testing

After setup (manual or automated):

```bash
# Check DNS propagation
watch -n 5 'dig +short fast.toper.dev'

# Test health endpoint
curl https://fast.toper.dev/health

# Expected: {"status":"ok"}
```

---

## Troubleshooting ExternalDNS

If DNS records aren't created:

```bash
# Check ExternalDNS logs
kubectl logs -l app=external-dns -f

# Common issues:
# - Invalid API token permissions
# - Domain filter doesn't match ingress hostname
# - Ingress doesn't have external IP/hostname

# Check ingress has address
kubectl get ingress fasttrack-api -o jsonpath='{.status.loadBalancer.ingress[0]}'
```

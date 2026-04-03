# FastTrack Observability

## Stack

| Component | Purpose | Address |
|-----------|---------|---------|
| **Prometheus** | Metrics collection & alert rules | Internal only (`monitoring` namespace) |
| **Grafana** | Dashboards & visualization | `https://grafana.fast.toper.dev` |
| **Loki + Promtail** | Log aggregation | Queried via Grafana |
| **Alertmanager** | Alert routing → email | Internal only |
| **Node Exporter** | Host CPU/memory/disk/network | Scraped by Prometheus |
| **kube-state-metrics** | k8s pod/deployment health | Scraped by Prometheus |

All components run in the `monitoring` k8s namespace and are defined under `backend/k8s/monitoring/`.

---

## Deploying the Monitoring Stack

```bash
# Create the namespace first
kubectl apply -f backend/k8s/monitoring/namespace.yaml

# Create required secrets (one-time setup)
kubectl create secret generic grafana-admin \
  --from-literal=username=admin \
  --from-literal=password=<STRONG_PASSWORD> \
  -n monitoring

kubectl create secret generic alertmanager-smtp \
  --from-literal=smtp_password=<GMAIL_APP_PASSWORD> \
  --from-literal=alert_email_to=<YOUR_EMAIL> \
  -n monitoring

# Deploy everything
kubectl apply -f backend/k8s/monitoring/
```

---

## Accessing Grafana

1. Browse to `https://grafana.fast.toper.dev`
2. Log in with the credentials from the `grafana-admin` secret
3. Dashboards are auto-provisioned on startup from ConfigMaps

### Adding a Dashboard

1. Build the dashboard in the Grafana UI
2. Export it: **Dashboard → Share → Export → Save to file**
3. Create a k8s ConfigMap:

```bash
kubectl create configmap grafana-dashboard-myname \
  --from-file=myname.json=./dashboard.json \
  -n monitoring \
  --dry-run=client -o yaml | kubectl apply -f -
```

4. Add the label so Grafana picks it up:

```bash
kubectl label configmap grafana-dashboard-myname grafana_dashboard=1 -n monitoring
```

---

## Application Metrics

The FastTrack API exposes a Prometheus `/metrics` endpoint (not externally reachable — scraped internally by Prometheus).

| Metric | Type | Description |
|--------|------|-------------|
| `http_requests_total` | Counter | HTTP requests by method, path, status |
| `http_request_duration_seconds` | Histogram | Request latency (p50/p95/p99) |
| `drive_recordings_total` | Counter | Drives saved to the database |
| `user_signups_total` | Counter | New user registrations by provider (apple/google) |
| `active_drives` | Gauge | Currently in-progress drives |
| `db_query_errors_total` | Counter | Failed database operations by operation |

---

## Alerts

Alerts are defined in `backend/k8s/monitoring/prometheus.yaml` under `groups[0].rules`. They are routed through Alertmanager which sends email via SMTP.

| Alert | Condition | Severity |
|-------|-----------|----------|
| `APIDown` | No app scrape data for >2 min | critical |
| `HighErrorRate` | HTTP 5xx >5% over 5 min | critical |
| `HighLatency` | p95 latency >2s over 5 min | warning |
| `DiskAlmostFull` | Disk usage >85% | warning |
| `PodCrashLooping` | Pod restart count >3 in 10 min | critical |
| `HighMemoryUsage` | Memory usage >90% | warning |
| `DBQueryErrors` | DB error rate spike | warning |

### Adding a New Alert

Edit `backend/k8s/monitoring/prometheus.yaml`, add a rule under `groups[0].rules`:

```yaml
- alert: MyNewAlert
  expr: <promql expression>
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Short description"
    description: "Longer description with {{ $value }}"
```

Then apply: `kubectl apply -f backend/k8s/monitoring/prometheus.yaml`

### Configuring Email Alerts

Alertmanager reads SMTP credentials from the `alertmanager-smtp` k8s secret:

```bash
# Update the destination email
kubectl patch secret alertmanager-smtp -n monitoring \
  --patch='{"stringData":{"alert_email_to":"your@email.com"}}'

# Update SMTP password (e.g., Gmail App Password)
kubectl patch secret alertmanager-smtp -n monitoring \
  --patch='{"stringData":{"smtp_password":"your-app-password"}}'
```

For Gmail: enable 2FA, then generate an App Password at <https://myaccount.google.com/apppasswords>.

---

## Structured Logging

All application logs are JSON (via Go's `slog` package) and collected by Promtail → Loki.

Every log line includes a `request_id` field for trace correlation across a single HTTP request.

**Querying logs in Grafana (Loki):**

```logql
# All errors for a specific request
{app="fasttrack"} | json | level="ERROR" | request_id="abc-123"

# Drive creation events in the last hour
{app="fasttrack"} | json | message="drive recorded"

# Auth events
{app="fasttrack"} | json | message=~"user signed up|user signed in"
```

---

## Runbooks

### API is down
1. Check pod status: `kubectl get pods -n default`
2. Check logs: `kubectl logs -l app=fasttrack-api --tail=100`
3. Check recent deploys: `kubectl rollout history deployment/fasttrack-api`
4. Rollback if needed: `kubectl rollout undo deployment/fasttrack-api`

### High error rate
1. Check Grafana "API Health" dashboard for the erroring endpoint
2. Query Loki for recent errors: `{app="fasttrack"} | json | level="ERROR"`
3. Check DB connectivity: `kubectl exec -it <pod> -- /bin/sh -c 'pg_isready -h $DB_HOST'`

### Disk almost full
1. Identify large files: `kubectl exec -it <prometheus-pod> -n monitoring -- df -h`
2. Reduce Prometheus retention: edit `--storage.tsdb.retention.time=15d` in `prometheus.yaml`
3. Consider adding a larger PVC

---

## Runbook Index

| Topic | Runbook |
|-------|---------|
| Releasing the app | [RELEASING.md](RELEASING.md) |
| Deploying the backend | [DEPLOYMENT.md](DEPLOYMENT.md) |
| Database schema & migrations | [DATABASE.md](DATABASE.md) |
| Local development | [DEVELOPMENT.md](DEVELOPMENT.md) |

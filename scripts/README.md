# Scripts

Operational scripts live in this directory.

## Active scripts

- `backup-restore.sh` — PostgreSQL backup/restore helpers.
- `deploy-local.sh` — legacy one-shot local/manual Kubernetes deploy (`DOMAIN` can be set to your deployed API host).
- `setup-external-dns.sh` — helper for Cloudflare ExternalDNS setup.

## Legacy scripts

These are kept for historical/local workflows and are not part of the primary production release path:

- `deploy-to-toper.sh`
- `quickstart.sh`
- `setup-github.sh`

The canonical production deploy path is the GitHub Actions workflow in `.github/workflows/backend-deploy.yml`.

## Parameterized legacy scripts

- `deploy-to-toper.sh` now expects `DEPLOY_SERVER` (and optionally `DEPLOY_DOMAIN`, `DEPLOY_NAMESPACE`, `DEPLOY_APP_NAME`).
- `setup-external-dns.sh` uses placeholder domain output text to avoid environment-specific hardcoding.

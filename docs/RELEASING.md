# Releasing FastTrack

This document describes the release process for both the backend and iOS app.

## Overview

FastTrack uses [semantic versioning](https://semver.org) (`MAJOR.MINOR.PATCH`) and [conventional commits](https://www.conventionalcommits.org/) to drive automated changelogs and releases.

**Commit message format:**
```
<type>(<scope>): <subject>

feat(social): add leaderboard pagination
fix(auth): handle expired apple token gracefully
chore(ci): update xcode version in workflow
docs(api): document /health endpoint
```

Enforced types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `ci`, `perf`, `revert`

---

## Versioning

The current version lives in [`VERSION`](../VERSION) at the repo root. Both the iOS build and backend Docker image pick this up automatically.

Update it before tagging a release:
```sh
echo "1.2.0" > VERSION
git add VERSION
git commit -m "chore(release): bump version to 1.2.0"
```

---

## Backend Release

The backend deploy pipeline has **two stages** that run automatically on every push to `main`:

1. **Build** — Docker image is built and pushed to GHCR
2. **Deploy → Staging** — auto-deploys to the `fasttrack-staging` k8s namespace (no approval needed)
3. **Deploy → Production** — waits for manual approval in the `production` GitHub environment, then deploys to `fasttrack-production`

| Environment | URL | Namespace | Approvals |
|-------------|-----|-----------|-----------|
| Staging | `https://staging.fast.toper.dev` | `fasttrack-staging` | Auto |
| Production | `https://fast.toper.dev` | `fasttrack-production` | Manual gate |

For a named release:
1. Update `VERSION`
2. Push a git tag: `git tag v1.2.0 && git push origin v1.2.0`
3. The [release workflow](.github/workflows/release.yml) will auto-generate the changelog and create a GitHub Release

---

## iOS Release

### Prerequisites (one-time setup)

1. **App Store Connect API key** — Generate at [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → Users & Access → Integrations → App Store Connect API. Store the `.p8` key file content as the `APP_STORE_CONNECT_API_KEY` GitHub secret, along with `APP_STORE_CONNECT_KEY_ID` and `APP_STORE_CONNECT_ISSUER_ID`.

2. **Fastlane Match repo** — Create a private GitHub repo for certificates (e.g. `yourorg/fasttrack-certs`). Update [`fastlane/Matchfile`](../ios/FastTrack/fastlane/Matchfile) with its URL. Store the match encryption password as `MATCH_PASSWORD` and a base64-encoded `user:token` as `MATCH_GIT_BASIC_AUTHORIZATION`.

3. **Appfile** — Fill in your Apple ID, team ID, and ITC team ID in [`fastlane/Appfile`](../ios/FastTrack/fastlane/Appfile).

4. **Xcode test target** — Open the project in Xcode, go to **File → New → Target → Unit Testing Bundle**, name it `FastTrackTests`, set Host Application to `FastTrack`. The test files in `FastTrackTests/` will be picked up automatically.

### TestFlight release (beta)

Push a version tag to trigger automatic TestFlight upload:
```sh
# 1. Update version
echo "1.2.0" > VERSION
git add VERSION
git commit -m "chore(release): bump to 1.2.0"

# 2. Tag and push
git tag v1.2.0
git push origin main --tags
```

The [ios-release workflow](.github/workflows/ios-release.yml) runs `fastlane beta` automatically.

### Manual TestFlight upload (local)
```sh
cd ios/FastTrack
bundle install
bundle exec fastlane beta
```

### App Store submission
```sh
cd ios/FastTrack
bundle exec fastlane release
```

This archives, exports, and submits for App Review. Automatic release is **off** — approve manually in App Store Connect.

---

## Required GitHub Secrets

Add these at: **GitHub repo → Settings → Secrets and variables → Actions → New repository secret**

### ✅ Available Now (Backend — set these first)

> **Where to add them:** In GitHub, go to **Settings → Environments**.
> - Create two environments: `staging` and `production`
> - Add `production` protection rules: restrict to `main` branch + add yourself as a required reviewer
> - Add the secrets below to **both** environments (each environment needs its own copy — staging can point to a staging DB, production to the real one)

**`KUBECONFIG`**
Base64-encoded kubeconfig giving kubectl access to your cluster. Generate:
```sh
# On your server / wherever kubectl is configured:
cat ~/.kube/config | base64 -w 0
```
Paste the output as the secret value. This replaces `SERVER_HOST`, `SERVER_USER`, `SERVER_SSH_PORT`, and `SSH_PRIVATE_KEY` — the workflow now deploys via kubectl directly.

**`JWT_SECRET`**
A random 64-character hex string used to sign JWTs. Generate one:
```sh
openssl rand -hex 32
```

**`DATABASE_URL`**
Postgres connection string. For staging and production you'll want separate databases:
```
# staging
postgres://fasttrack:PASSWORD@localhost:5432/fasttrack_staging?sslmode=disable
# production
postgres://fasttrack:PASSWORD@localhost:5432/fasttrack?sslmode=disable
```

**`APPLE_APP_BUNDLE_ID`**
Value: `dev.toper.FastTrack`

**`BASE_URL`**
- Staging: `https://staging.fast.toper.dev`
- Production: `https://fast.toper.dev`

---

### ⏳ Requires Apple Developer Account Approval (iOS — set when ready)

**`APP_STORE_CONNECT_KEY_ID`**
Found at: [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → Users & Access → Integrations → App Store Connect API → Generate Key.
It's the 10-character alphanumeric Key ID shown next to your key (e.g. `ABC1234DEF`).

**`APP_STORE_CONNECT_ISSUER_ID`**
Shown at the top of the same App Store Connect API page.
It's a UUID: `69a6de70-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

**`APP_STORE_CONNECT_API_KEY`**
Download the `.p8` file when you create the key (only downloadable once). Format as JSON:
```json
{
  "key_id": "ABC1234DEF",
  "issuer_id": "69a6de70-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "key": "-----BEGIN PRIVATE KEY-----\nMIGTAgEAMBMG...\n-----END PRIVATE KEY-----"
}
```
The `key` value is the `.p8` file contents with actual newlines replaced by `\n`.

**`MATCH_PASSWORD`**
A strong password you choose — Fastlane Match uses this to encrypt certificates stored in the certs repo. Pick something and save it in your password manager:
```sh
openssl rand -base64 24
```

**`MATCH_GIT_BASIC_AUTHORIZATION`**
Required for CI to access your private certs repo (see Fastlane Matchfile).
Create a GitHub Personal Access Token with `repo` scope, then:
```sh
echo -n "your-github-username:ghp_yourPersonalAccessToken" | base64
```
Paste the base64 output as the secret value.

---

### Summary Table

| Secret | Environment | Workflow | Status |
|--------|-------------|----------|--------|
| `KUBECONFIG` | staging + production | backend-deploy | ✅ Set now |
| `JWT_SECRET` | staging + production | backend-deploy | ✅ Set now |
| `DATABASE_URL` | staging + production | backend-deploy | ✅ Set now (different DB per env) |
| `APPLE_APP_BUNDLE_ID` | staging + production | backend-deploy | ✅ Set now (`dev.toper.FastTrack`) |
| `BASE_URL` | staging + production | backend-deploy | ✅ Set now (different URL per env) |
| `APP_STORE_CONNECT_KEY_ID` | — | ios-release | ⏳ After Developer approval |
| `APP_STORE_CONNECT_ISSUER_ID` | — | ios-release | ⏳ After Developer approval |
| `APP_STORE_CONNECT_API_KEY` | — | ios-release | ⏳ After Developer approval |
| `MATCH_PASSWORD` | — | ios-release | ⏳ Choose now, set later |
| `MATCH_GIT_BASIC_AUTHORIZATION` | — | ios-release | ⏳ After Developer approval |

---

## Changelog

The [CHANGELOG.md](../CHANGELOG.md) is auto-updated by the release workflow using [git-cliff](https://git-cliff.org/). Configuration is in [`cliff.toml`](../cliff.toml).

To preview the next release notes locally:
```sh
brew install git-cliff
git cliff --unreleased
```

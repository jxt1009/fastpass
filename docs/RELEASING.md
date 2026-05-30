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

GitHub Actions enforces this in two places:

1. Pull requests must use a semantic PR title (`feat: ...`, `fix(api): ...`, etc.), which keeps squash merges release-friendly.
2. `main` is branch-protected, so changes should land through pull requests rather than direct pushes.

If you rely on PRs for release notes, prefer **Squash and merge** for human-authored changes so the PR title becomes the commit that lands on `main`.

---

## Versioning

The current version lives in [`VERSION`](../VERSION) at the repo root. Both the iOS build and backend Docker image pick this up automatically.

`release-please` now owns the version bump PR and tag creation. It updates `VERSION` for you from the conventional commits that have landed on `main`.

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

For a named release from the protected `main` branch:
1. Merge conventional commits into `main`
2. Wait for the **Release Please** workflow to open or update the release PR
3. Merge the release PR
4. The release PR merge pushes a `vX.Y.Z` tag automatically
5. The [release workflow](../.github/workflows/release.yml) generates the GitHub Release notes from that tag
6. If you need to publish an existing tag with the latest workflow logic, run the **Release** workflow manually and provide the tag name (for example `v0.1.1`)

---

## iOS Release

### Prerequisites (one-time setup)

1. **App Store Connect API key** — Generate at [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → Users & Access → Integrations → App Store Connect API. Keep the `.p8` file locally for Fastlane, and store its contents in the `APP_STORE_CONNECT_API_KEY` GitHub secret along with `APP_STORE_CONNECT_KEY_ID` and `APP_STORE_CONNECT_ISSUER_ID`. The workflow accepts the raw `.p8` contents, the same contents with `\n` escapes, or a base64-encoded `.p8` file. **Recommended:** use base64 to avoid paste/newline issues:
   ```sh
   base64 < AuthKey_XXXXXXXXXX.p8 | tr -d '\n'
   ```

2. **Fastlane local env file** — Run `./scripts/setup_apple_release_env.sh` from [`ios/FastTrack`](../ios/FastTrack/) once Apple finishes approving your account. That writes `ios/FastTrack/.env.fastlane` with non-secret identifiers/paths for local Fastlane runs, including `APPLE_ID` and `TEAM_ID`, and stores `MATCH_PASSWORD` in your macOS Keychain under the `com.toper.FastTrack.fastlane` service.

3. **Fastlane Match repo** — Create a private GitHub repo for certificates (e.g. `yourorg/fasttrack-certs`) and provide that URL to the setup script. Store the match encryption password as `MATCH_PASSWORD` and a base64-encoded `user:token` as `MATCH_GIT_BASIC_AUTHORIZATION` for CI.

For local development, prefer Keychain-backed secrets over plaintext `.env.fastlane` entries. The setup script already stores `MATCH_PASSWORD` in Keychain; keep `.p8` files outside the repo with restrictive permissions like `chmod 600`.

4. **Apple revocation key for account deletion** — Create a **Sign in with Apple** key in the Apple Developer portal. The same setup script can print the backend secrets you need to add later: `APPLE_TEAM_ID`, `APPLE_KEY_ID`, and `APPLE_PRIVATE_KEY`.

5. **Xcode test target** — The shared `FastTrack` scheme already includes `FastTrackTests`; CI and Fastlane both run tests through the app scheme. GitHub Actions now runs the iOS workflows on `macos-26` with Xcode 26 so TestFlight uploads meet App Store Connect's minimum SDK requirement.

6. **Google Sign-In client ID** — Add `IOS_GOOGLE_CLIENT_ID` as a repository GitHub Actions secret with the iOS OAuth client ID for `com.toper.FastTrack`. The release workflow injects it into `FastTrack/Secrets.swift` at build time. If `IOS_GOOGLE_CLIENT_ID` is not set, the workflow falls back to `GOOGLE_CLIENT_ID`.

### TestFlight release (beta)

Merge the release PR to trigger automatic TestFlight upload. The release PR creates the version tag, and the [ios-release workflow](../.github/workflows/ios-release.yml) runs `fastlane beta` automatically for stable `v*` tags.

### Manual TestFlight upload (local)
```sh
cd ios/FastTrack
bundle install
./scripts/setup_apple_release_env.sh
bundle exec fastlane beta
```

### App Store submission
```sh
cd ios/FastTrack
./scripts/setup_apple_release_env.sh
bundle exec fastlane release
```

This archives, exports, and submits for App Review. Automatic release is **off** — approve manually in App Store Connect.

---

## Required GitHub Secrets

Add these at: **GitHub repo → Settings → Secrets and variables → Actions → New repository secret**

**`RELEASE_PLEASE_TOKEN`**
A Personal Access Token (classic) or GitHub App token with permission to open release PRs and push tags. Do **not** use the default `GITHUB_TOKEN` here; tags created with `GITHUB_TOKEN` will not trigger the downstream `release.yml` and `ios-release.yml` workflows.

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
Value: `com.toper.FastTrack`

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
Download the `.p8` file when you create the key (only downloadable once). Recommended: store a base64-encoded copy of the file in the GitHub secret:
```sh
base64 < AuthKey_XXXXXXXXXX.p8 | tr -d '\n'
```
The workflow also accepts raw `.p8` contents and `\n`-escaped contents.

**`APPLE_ID`**
The Apple ID email for the App Store Connect account that owns the app.

**`TEAM_ID`**
Your 10-character Apple Developer Team ID.

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
| `APPLE_APP_BUNDLE_ID` | staging + production | backend-deploy | ✅ Set now (`com.toper.FastTrack`) |
| `BASE_URL` | staging + production | backend-deploy | ✅ Set now (different URL per env) |
| `RELEASE_PLEASE_TOKEN` | — | release-please | ✅ Set now |
| `APP_STORE_CONNECT_KEY_ID` | — | ios-release | ⏳ After Developer approval |
| `APP_STORE_CONNECT_ISSUER_ID` | — | ios-release | ⏳ After Developer approval |
| `APP_STORE_CONNECT_API_KEY` | — | ios-release | ⏳ After Developer approval |
| `APPLE_ID` | — | ios-release | ⏳ After Developer approval |
| `TEAM_ID` | — | ios-release | ⏳ After Developer approval |
| `MATCH_PASSWORD` | — | ios-release | ⏳ Choose now, set later |
| `MATCH_GIT_BASIC_AUTHORIZATION` | — | ios-release | ⏳ After Developer approval |
| `IOS_GOOGLE_CLIENT_ID` | — | ios-release | ✅ Set now for Google Sign-In builds |

---

## Release notes

GitHub Releases are generated by the tag-triggered release workflow using [git-cliff](https://git-cliff.org/). Configuration is in [`cliff.toml`](../cliff.toml). `release-please` intentionally skips changelog generation in this repo so `git-cliff` remains the single source of truth for release notes formatting.

Historical tag pushes still use the workflow file that existed on that tagged commit, so a fix to `release.yml` on `main` does not retroactively change an already-failed historical run. Use the manual **Release** workflow dispatch to publish those older tags with the current workflow instead.

To preview the next release notes locally:
```sh
brew install git-cliff
git cliff --unreleased
```

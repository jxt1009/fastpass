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

The backend deploys **automatically on every push to `main`** via the [backend-deploy](.github/workflows/backend-deploy.yml) workflow. No manual steps needed for rolling deployments.

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

| Secret | Used by | Description |
|--------|---------|-------------|
| `JWT_SECRET` | backend-deploy | 64-char random string for JWT signing |
| `DATABASE_URL` | backend-deploy | Postgres connection string |
| `SERVER_HOST` | backend-deploy | SSH hostname of the server |
| `SERVER_USER` | backend-deploy | SSH username (e.g. `deploy`) |
| `SSH_PRIVATE_KEY` | backend-deploy | Private key for SSH deploy access |
| `APPLE_APP_BUNDLE_ID` | backend-deploy | App bundle ID (e.g. `dev.toper.FastTrack`) |
| `BASE_URL` | backend-deploy | Public base URL (e.g. `https://fast.toper.dev`) |
| `APP_STORE_CONNECT_API_KEY` | ios-release | Full `.p8` key file content (JSON wrapper) |
| `APP_STORE_CONNECT_KEY_ID` | ios-release | Key ID from App Store Connect |
| `APP_STORE_CONNECT_ISSUER_ID` | ios-release | Issuer ID from App Store Connect |
| `MATCH_PASSWORD` | ios-release | Fastlane match encryption password |
| `MATCH_GIT_BASIC_AUTHORIZATION` | ios-release | Base64 `user:token` for match repo access |

---

## Changelog

The [CHANGELOG.md](../CHANGELOG.md) is auto-updated by the release workflow using [git-cliff](https://git-cliff.org/). Configuration is in [`cliff.toml`](../cliff.toml).

To preview the next release notes locally:
```sh
brew install git-cliff
git cliff --unreleased
```

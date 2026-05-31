# ADR-0003: Release-please for Automated Versioning

**Date:** 2026-05-31  
**Status:** Accepted

## Context

Version bumps and changelog entries were previously manual. This led to inconsistent changelog formatting, missed entries, and friction when cutting releases. The project already enforces Conventional Commits, so automated tooling that reads commit messages can generate changelogs without additional developer effort.

## Decision

Use [release-please](https://github.com/googleapis/release-please) to automate versioning and changelog generation:

- `release-please-config.json` configures the release type and versioned components.
- `.release-please-manifest.json` tracks the current version.
- The `release-please.yml` workflow opens a "Release PR" on every push to `main` that bumps `VERSION` and updates `CHANGELOG.md` based on Conventional Commits since the last release.
- Merging the Release PR creates a GitHub Release and a `v*` tag.
- A separate `release.yml` workflow uses `git-cliff` to generate polished release notes on the GitHub Release.

## Options considered

| Option | Pros | Cons |
|--------|------|------|
| Manual versioning (previous) | Full control | Error-prone; easy to forget; inconsistent |
| release-please (chosen) | Automatic; integrates with Conventional Commits; PR-based | Requires Conventional Commit discipline |
| semantic-release | Very full-featured | More complex config; pushes directly to main |

## Consequences

### Positive
- Release PRs are created automatically; developers only need to merge them.
- `CHANGELOG.md` and `VERSION` are always up to date.
- GitHub Releases include structured release notes.

### Negative / trade-offs
- Relies on consistent use of Conventional Commit prefixes (`feat:`, `fix:`, etc.).
- Release PR must be manually reviewed and merged; fully unattended releases are not supported by design.

## References

- `release-please-config.json`
- `.release-please-manifest.json`
- `.github/workflows/release-please.yml`
- `.github/workflows/release.yml`
- `docs/RELEASING.md`

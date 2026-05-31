# TestFlight release notes normalization plan

## Problem

TestFlight's **What to Test** field does not render markdown well, and the current iOS release workflow forwards the full GitHub release markdown body.  
Because release notes are generated with git-cliff, the body can include historical sections, which makes TestFlight notes noisy and too long.

## Scope

- Keep GitHub release notes formatting unchanged (markdown-rich for GitHub UI).
- Change only how TestFlight notes are generated in the iOS release workflow.
- Keep the existing stable-tag gating and Fastlane upload behavior.

## Implementation steps

1. Add a small transformer script under `ios/FastTrack/scripts/` that:
   - extracts only the latest release section from the release body,
   - keeps only user-facing groups (`Features`, `Bug Fixes`, `Performance`),
   - converts markdown formatting to plain text suitable for TestFlight,
   - truncates output to App Store Connect limits.
2. Update `.github/workflows/ios-release.yml` to pass the fetched release body through the transformer and set `FL_WHATS_NEW` from transformed output.
3. Update `docs/RELEASING.md` to document the split behavior:
   - GitHub releases stay markdown,
   - TestFlight notes are latest-only plain text.

## Validation

- Generate notes from a representative git-cliff release body and confirm:
  - output contains only one release version section,
  - output includes only user-facing groups,
  - output contains no markdown link/heading formatting,
  - output length stays within limits for `FL_WHATS_NEW`.

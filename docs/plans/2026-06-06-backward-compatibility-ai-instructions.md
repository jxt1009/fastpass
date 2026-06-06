# Backward Compatibility — AI Tool Instructions

**Date:** 2026-06-06
**Branch:** `docs/backward-compat-ai-instructions` (worktree at `.worktrees/docs/backward-compat-ai-instructions`)

## Status

- [x] Worktree + plan artifact
- [ ] Edit `AGENTS.md` — add backward compatibility section
- [ ] Edit `.github/copilot-instructions.md` — add backward compatibility under "Key conventions"
- [ ] Edit `.github/pull_request_template.md` — add backward compat checklist item
- [x] Commit + PR
- [x] Fix: "always add, never remove" contradicted migrations.go RenameColumn — rephrased to "additive by default" with note on guarded renames (copilot feedback)

## Motivation

We now have our first external user (non-tech-savvy). The app may not be updated
immediately after every release. All server-side changes must tolerate old
clients. Any change that would require a client update must be explicitly called
out and coordinated.

## Audit — Existing Coverage of Backward Compatibility

| File | What it says |
|---|---|
| `AGENTS.md` | Nothing about backward compatibility |
| `.github/copilot-instructions.md` | Situational notes only: garage legacy fields, route_data versioning, auth restore behavior. No overarching principle. |
| `.github/pull_request_template.md` | Has "Release / Deployment Impact" section but no explicit backward-compat checklist item |
| `~/.config/opencode/AGENTS.md` | Behavioral guidelines for opencode itself — no project-specific backward compat needed |

## Changes Required

### 1. `AGENTS.md` — New Section 5: Backward Compatibility

Add after the existing Section 4 (Planning artifacts). This is the primary
opencode directive. Covers:

- **API contract is additive only**: never remove or rename JSON fields.
  Old clients gracefully ignore unknown fields.
- **Append-only migrations**: new columns nullable or with defaults.
  Never drop columns or change types without a careful plan.
- **Client-aware changes**: if a change genuinely requires an app update,
  document the cutover in the plan artifact and PR body.
- **Litmus test**: "Would this break someone running last week's app release?"

### 2. `.github/copilot-instructions.md` — Add to "Key conventions"

Similar principles, but with concrete iOS/backend examples matching the
existing detail level of this file.

### 3. `.github/pull_request_template.md` — Checklist item

Add `- [ ] Backward compatible (old clients won't break)`.

## Rationale

All three files (`AGENTS.md`, `.github/copilot-instructions.md`,
`opencode.json` reference chain) are consumed by AI tools. Adding the
principle to all of them ensures it surfaces regardless of which tool a
contributor uses.

`opencode.json` already references both instruction files, so no change
needed there.

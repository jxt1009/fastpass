# Productionization Implementation Plan (Phased)

## Phase 1 — Repository and workflow clarity

- [x] Move root operational scripts under `scripts/` with compatibility wrappers.
- [x] Mark `website/` as legacy/deprecated.
- [x] Align deployment/release docs with staged deployment namespaces and secret names.
- [x] Add top-level repository architecture map in `README.md`.
- [x] Add baseline governance defaults: `.editorconfig`, `CODEOWNERS`, PR template.

## Phase 2 — Backend architecture hardening

- [ ] Introduce `cmd/` + `internal/` backend package layout.
- [ ] Split monolithic backend responsibilities into domain-focused modules.
- [ ] Replace startup `AutoMigrate`-driven schema changes with explicit versioned migrations.

## Phase 3 — iOS maintainability

- [ ] Reduce singleton usage with clearer dependency injection boundaries.
- [ ] Split oversized managers/views into smaller feature-owned components.
- [ ] Establish consistent app-state ownership for auth/profile/drive/settings flows.

## Phase 4 — Workflow and quality polish

- [ ] Extract repeated backend deploy workflow logic into reusable actions/workflows.
- [ ] Add workflow/docs/config quality checks in CI.
- [ ] Formalize repository standards/ADRs for structural changes and debt tracking.

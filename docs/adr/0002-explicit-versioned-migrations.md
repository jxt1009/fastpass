# ADR-0002: Explicit Versioned Migrations Over AutoMigrate

**Date:** 2026-05-30  
**Status:** Accepted

## Context

The backend previously used GORM's `AutoMigrate` to apply schema changes on every startup. While convenient during early development, `AutoMigrate` is not safe for production because it can silently drop columns on certain database engines, does not support data migrations, and provides no rollback path. It also makes it impossible to audit what schema changes have been applied or when.

## Decision

Replace `AutoMigrate` with an explicit versioned migration system:

- Each schema change is expressed as a numbered SQL migration in `backend/internal/app/migrations.go`.
- A `schema_migrations` table records which migrations have been applied.
- Migrations run at startup via `runMigrations()` in `bootstrap.go`.
- Migrations are idempotent: re-running a migration that is already recorded is a no-op.

## Options considered

| Option | Pros | Cons |
|--------|------|------|
| GORM AutoMigrate (previous) | Zero boilerplate | Unsafe in production; no rollback; no audit trail |
| External tool (golang-migrate, goose) | Rich feature set; rollback support | Adds dependency; requires migration files on disk |
| Inline versioned migrations (chosen) | No extra dependency; auditable; safe at startup | Manual rollback (forward-only by default) |

## Consequences

### Positive
- Schema changes are explicit and reviewable in code.
- Applied migrations are tracked; duplicate runs are safe.
- No surprise schema alterations on production restarts.

### Negative / trade-offs
- Rollback requires writing a reverse migration manually.
- Developers must remember to add a migration entry for every schema change.

## References

- `backend/internal/app/migrations.go`
- `backend/internal/app/bootstrap.go`

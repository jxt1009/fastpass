# ADR-0001: Backend `cmd/`+`internal/` Package Layout

**Date:** 2026-05-30  
**Status:** Accepted

## Context

The original backend was a flat collection of Go files in a single package under `backend/`. As the application grew, the lack of package boundaries made it difficult to reason about dependencies, control what was exported, and write focused tests. The monolithic `main.go` mixed routing, middleware, domain logic, and startup concerns in a single file.

## Decision

Adopt the standard Go project layout:

- `backend/cmd/server/` — the binary entrypoint (`main.go`). Thin; only initialises and starts the app.
- `backend/internal/app/` — application bootstrap, route registration, and domain logic. The `internal/` prefix prevents accidental import from outside the module.

Route registration is split into domain-focused files (`routes_auth.go`, `routes_social.go`, etc.) rather than one monolithic file.

## Options considered

| Option | Pros | Cons |
|--------|------|------|
| Keep flat layout | No migration effort | Increasingly hard to navigate; no enforced encapsulation |
| `cmd/`+`internal/` (chosen) | Clear entrypoint; Go-idiomatic; enforces encapsulation | Requires moving existing files |
| Full pkg/ layout | Maximum flexibility | Over-engineered for current scale |

## Consequences

### Positive
- Clear separation between "run the program" and "application logic".
- `internal/` prevents unintentional external imports.
- Easier to split into sub-packages later without touching `cmd/`.

### Negative / trade-offs
- One-time migration effort for existing code.
- Slightly deeper import paths.

## References

- `backend/cmd/server/main.go`
- `backend/internal/app/main.go`
- [Standard Go Project Layout](https://github.com/golang-standards/project-layout)

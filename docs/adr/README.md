# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the FastTrack project.

## What is an ADR?

An ADR is a short document that captures an important architectural decision, its context, the options considered, and the rationale for the choice. ADRs create a lightweight audit trail of *why* the codebase looks the way it does.

## When to write an ADR

Write an ADR when a decision:

- Affects multiple components, modules, or team members
- Is hard to reverse, or has significant trade-offs
- Would otherwise be re-litigated in future code reviews
- Involves choosing between meaningful alternatives

Small, obvious choices (e.g. picking a variable name) do not need an ADR.

## ADR lifecycle

| Status | Meaning |
|--------|---------|
| **Proposed** | Under discussion; not yet accepted |
| **Accepted** | Decision is in effect |
| **Deprecated** | Superseded but kept for historical context |
| **Superseded by ADR-NNNN** | Replaced by a newer decision |

## Naming convention

Files are named `NNNN-short-title.md` where `NNNN` is a zero-padded sequential number.

## Template

See [template.md](template.md) for the standard format.

## Index

| # | Title | Status |
|---|-------|--------|
| [0001](0001-backend-cmd-internal-layout.md) | Backend `cmd/`+`internal/` package layout | Accepted |
| [0002](0002-explicit-versioned-migrations.md) | Explicit versioned migrations over AutoMigrate | Accepted |
| [0003](0003-release-please-automation.md) | Release-please for automated versioning | Accepted |
| [0004](0004-kubernetes-staged-deployment.md) | Staged Kubernetes deployment (staging → production) | Accepted |

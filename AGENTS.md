# Project instructions for opencode

## 1. Always use a git worktree

Before starting any work, create a dedicated git worktree for the feature/fix branch:

```bash
git worktree add ../fasttrack-<branch-name> <base-branch>
```

Work in the worktree directory, commit there, and push from there. Remove the worktree after the PR is merged.

Before pushing, always rebase the branch onto `main` (or the target base branch) to keep history linear:

```bash
git rebase main
```

## 2. Conventional commits

All commits must follow the [Conventional Commits](https://www.conventionalcommits.org/) specification. This repo enforces it via commitlint.

Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.

Format:
```
<type>(<scope>): <description>

<body>
```

## 3. Opening PRs

After pushing a branch, always create a PR with `gh pr create` and populate both the title and body. The title should mirror the conventional commit style. The body should summarize what changed and why.

## 4. Planning artifacts in repo

For any multi-step implementation (feature work, refactors, or non-trivial fixes), create and maintain a plan in `docs/plans/` using a date-prefixed filename (for example `2026-05-31-testflight-release-notes.md`).

Treat these plans as version-controlled project artifacts: keep them in-repo, update them at major milestones, and avoid keeping substantive implementation plans only in ephemeral session files.

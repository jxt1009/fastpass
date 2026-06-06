# Project instructions for opencode

## 1. Always use a git worktree (and always start from latest main)

**Critical:** This repo has frequent worktree + rebase conflicts when branches
drift from main. To avoid this:

1. **Always** start from a fresh main:
   ```bash
   git checkout main
   git pull origin main
   ```

2. Then create the worktree from that up-to-date main:
   ```bash
   git worktree add .worktrees/<branch-name> main
   ```

3. Work exclusively in `.worktrees/<branch-name>/`

4. Before any push or PR update, rebase onto the *latest* origin/main:
   ```bash
   cd .worktrees/<branch-name>
   git fetch origin main
   git rebase origin/main
   ```

5. Push with `--force-with-lease` after rebase.

6. Clean up after PR merge:
   ```bash
   git worktree remove .worktrees/<branch-name>
   ```

**Never** create a worktree or rebase without first pulling the absolute latest `main`. This is the #1 cause of repeated .gitignore and other conflicts.

We use `.worktrees/` (plural) as the convention for local worktrees inside the repo (see existing ones and `.gitignore`).

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

## 5. Backward Compatibility

We have external users who may not update the app immediately. Every server-side
change must tolerate old clients unless explicitly justified.

- **API contract is additive only.** Never remove or rename JSON response fields.
  Old clients gracefully ignore unknown fields; new clients can use added fields.
- **Database migrations are additive by default.** New columns must be nullable
  or have safe defaults. Avoid drops, type changes, and renames. If a rename is
  necessary, it must be guarded (check old column exists and new doesn't) and
  have a documented cutover plan.
- **Client-aware changes.** If a change genuinely requires an app update (e.g. a
  new request format), document the cutover plan in the plan artifact and PR
  body. The PR title or body should call out the compatibility break.
- **Litmus test for every change:** "Would this break someone running last
  week's app release?" If the answer is yes, rethink the approach or document
  the coordination required.

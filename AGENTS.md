# Responsay macOS repository instructions

## Repository workflow

- GitHub `semantic-craft/responsay-macos` is the primary code, branch, review, pull-request, and issue repository. The `origin` remote must point to GitHub; `cursor` preserves the former Cursor Origin repository for historical work.
- Start branches from a freshly fetched `origin/main`; verify that `origin` points to GitHub before starting work.
- Everything lands through a GitHub pull request. Never push directly to `main`, never force-push it, and use a merge commit rather than squash or rebase merge.
- GitHub Actions runs portable policy and privacy guards plus Apple Silicon macOS Swift and Xcode build/test gates. The exact contracts live in `docs/operations/ci.md`.
- Before merge, run the relevant local gates from `CONTRIBUTING.md`, review the complete diff, require the remote checks documented in `docs/operations/ci.md`, update the branch from current `origin/main`, and verify the remote merge commit by object ID and ancestry.
- One worktree has one owner. Do not reset, prune, delete, or reuse another agent's worktree. Remove only a task-created worktree whose changes are merged, whose status is clean, which has no unique commits or open PR, and which no process is using.
- Preserve unique branches and worktrees from Cursor Origin. Continue selected work through a GitHub PR after reviewing its diff; do not mirror refs or automatically merge historical work.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in this repository's GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the five canonical triage labels without renaming. See `docs/agents/triage-labels.md`.

### Domain docs

This repository uses a single-context domain-doc layout. See `docs/agents/domain.md`.

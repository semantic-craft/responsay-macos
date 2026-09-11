# Responsay macOS repository instructions

## Repository workflow

- GitHub `semantic-craft/responsay-macos` is the primary code, branch, review, pull-request, and issue repository. The `origin` remote must point to GitHub. The former Cursor Origin repository has been retired; do not recreate its remote.
- When starting a branch, fetch `origin/main` and verify that `origin` points to GitHub. Bounded work in an existing checkout preserves its current changes.
- Everything lands through a GitHub pull request. Never push directly to `main`, never force-push it, and use a merge commit rather than squash or rebase merge.
- GitHub Actions runs portable policy and privacy guards plus Apple Silicon macOS Swift and Xcode build/test gates. The exact contracts live in `docs/operations/ci.md`.
- Before merge, run the relevant local gates from `CONTRIBUTING.md`, review the complete diff, require the remote checks documented in `docs/operations/ci.md`, update the branch from current `origin/main`, and verify the remote merge commit by object ID and ancestry.
- One worktree has one owner. Do not reset, prune, delete, or reuse another agent's worktree. Remove only a task-created worktree whose changes are merged, whose status is clean, which has no unique commits or open PR, and which no process is using.
- GitHub is the only development forge. Historical Cursor refs were archived before retirement; any recovered work must be reviewed through a GitHub PR.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in this repository's GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the five canonical triage labels without renaming. See `docs/agents/triage-labels.md`.

### Domain docs

This repository uses a single-context domain-doc layout. See `docs/agents/domain.md`.

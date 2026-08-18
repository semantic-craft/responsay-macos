# Responsay macOS repository instructions

## Repository workflow

- Cursor Origin `xianwei/responsay-macos` is the code, branch, review, and pull-request forge. GitHub `semantic-craft/responsay-macos` is the archival repository and issue tracker; it remains public only while it serves the current Sparkle feed and DMG.
- Start branches from a freshly fetched `origin/main`; never branch from a stale local ref or from the `github` archive remote.
- Everything lands through an Origin pull request. Never push directly to `main`, never force-push it, and use a merge commit rather than squash or rebase merge.
- Depot owns only the portable Linux-safe policy and privacy guards. Buildkite hosted Apple Silicon macOS owns the native Swift, Xcode, AppKit, and AVFoundation evidence. The exact contracts live in `docs/operations/ci.md`.
- Before merge, run the relevant local gates from `CONTRIBUTING.md`, review the complete diff, require both remote checks, update the branch from current `origin/main`, and verify the remote merge commit by object ID and ancestry.
- One worktree has one owner. Do not reset, prune, delete, or reuse another agent's worktree. Remove only a task-created worktree whose changes are merged, whose status is clean, which has no unique commits or open PR, and which no process is using.
- GitHub issues are the only permanent development-governance exception. Claim and close work there, but do not open new GitHub code pull requests after the migration. Until distribution moves, a maintainer may fast-forward `github/main` to the exact reviewed `origin/main` object solely to publish the feed and refresh the archive; never mirror or publish a local branch.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in this repository's GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the five canonical triage labels without renaming. See `docs/agents/triage-labels.md`.

### Domain docs

This repository uses a single-context domain-doc layout. See `docs/agents/domain.md`.

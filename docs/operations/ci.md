# GitHub and CI operations

GitHub `semantic-craft/responsay-macos` is the primary repository for code, branches, reviews, pull requests, issues, CI, and releases. The canonical clone URL is:

```text
git@github.com:semantic-craft/responsay-macos.git
```

## Local remotes and preserved work

- `origin`: GitHub, used for normal fetch, branches, pull requests, and tags.
- `cursor`: the former Cursor Origin repository, retained for historical branches. Do not use it for new development or mirror refs.

Before starting work, check `git remote -v`; old clones may still call Cursor Origin `origin` and GitHub `github`. Rename the former to `cursor`, then the latter to `origin`, and set `remote.pushDefault` to `origin`. Git remote renaming preserves upstream associations. Review any branch still tracking `cursor` before continuing it through a GitHub PR; do not overwrite its worktree.

At the return-to-GitHub audit on 2026-09-07, both main branches were `e51bd89d016b49feb4be646a9bfa617f07de29bf`, and Cursor Origin had no open PRs. Its `codex/r2-joint-release` and `codex/tts-configured-default` branches were absent from GitHub and were preserved in place. GitHub PR #101 was already open. These are audit facts, not instructions to resume or merge those tasks; recheck live state when handling them.

## CI ownership

GitHub Actions owns the development gates in `.github/workflows/ci.yml`:

| Required check | Runner | Responsibility |
| --- | --- | --- |
| Static policy and privacy guards | `ubuntu-24.04` | Public-source allowlist, deterministic credential patterns, and source/privacy lint tests |
| Privacy, tests, and macOS build | `macos-26` (Apple Silicon) | Full Gitleaks/TruffleHog scans, ResponsayCore tests, generated Xcode project, app test build, and executed ResponsayMac tests |

The macOS job asserts `Darwin` and `arm64`. Linux checks do not substitute for AppKit, AVFoundation, Xcode, or native tests. All action references are pinned to commit SHAs. Dependabot maintains GitHub Actions updates. The external Swift packages are pinned in `project.yml`; review and update those pins in ordinary PRs because Dependabot does not manage the XcodeGen manifest. CodeQL runs separately in `.github/workflows/codeql.yml`.

Use `gh pr checks --repo semantic-craft/responsay-macos <number>` and `gh run view --repo semantic-craft/responsay-macos <run-id> --log-failed` to diagnose failures. A missing, queued, skipped, or running required check is not a pass. No signing, notarization, release, or provider credentials belong in CI. Microphone, accessibility, hotkey, insertion, Keychain, and screen-recording acceptance still requires a real Mac.

## Pull requests and main protection

All changes land through a GitHub PR with a merge commit. Require an up-to-date branch, resolved review threads, and both exact checks above from GitHub Actions. Block force pushes and deletion of `main`; do not use administrative bypass to evade checks. Before merge, fetch GitHub and confirm `origin/main` is an ancestor of the PR branch, complete the relevant local gates, and review the complete diff. After merge, verify the remote merge object and its ancestry.

## Public distribution

The Sparkle feed, DMG, README links, and `responsay.com` redirects continue using GitHub. Keep their public access intact. Publishing remains the maintainer procedure in `docs/RELEASING.md`; CI does not sign or publish releases. Appcast updates land through GitHub PRs with no archival sync to another forge.

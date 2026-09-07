# GitHub and CI operations

GitHub `semantic-craft/responsay-macos` is the primary repository for code, branches, reviews, pull requests, issues, CI, and releases. The canonical clone URL is:

```text
git@github.com:semantic-craft/responsay-macos.git
```

## Local remotes and preserved work

- `origin`: GitHub, used for normal fetch, branches, pull requests, and tags.
- No secondary development remote. The former Cursor Origin repository was archived and deleted on 2026-09-07.

Before starting work, check `git remote -v`; `origin` must point to GitHub. For an older clone, audit unique commits and uncommitted work before removing the retired Cursor remote and configuring GitHub as `origin`. Set `remote.pushDefault` to `origin`. Do not overwrite a working tree during migration.

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

Release distribution uses R2 for the Sparkle feed and DMG while keeping GitHub as the primary source repository. Complete the R2 domain, signed-artifact, redirect, and real-client transition checks in `docs/RELEASING.md` before release. Keep the existing GitHub feed public for installed clients. CI does not sign or publish releases, and no source mirror is part of R2 distribution.

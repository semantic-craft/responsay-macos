# Origin and CI operations

Cursor Origin is the code, branch, review, and pull-request forge for this repository. GitHub is the private archival repository and remains the issue tracker. The canonical clone URL is:

```text
https://origin.cursor.com/xianwei/responsay-macos.git
```

Keep the local remotes distinct:

- `origin`: Cursor Origin, used for normal fetch, branches, pull requests, and tags.
- `github`: `semantic-craft/responsay-macos`, retained as the private archive and issue tracker. It is not a source for new development branches and is not mirrored automatically.

## Public distribution boundary

Moving development to Origin does not by itself move app distribution. The current `SUFeedURL`, release script, README download link, and `responsay.com` redirects still depend on unauthenticated access to GitHub raw files and release assets. Making `semantic-craft/responsay-macos` private before replacing and testing those public endpoints would break Sparkle updates and the public DMG download.

The GitHub visibility change is therefore the final distribution gate: first move the feed and DMG to an explicitly selected public host, update the tracked URLs, and prove both old-client and current-client download paths. Do not treat an authenticated maintainer request as public acceptance.

## CI ownership

| Service | File | Responsibility |
| --- | --- | --- |
| Depot CI | `.depot/workflows/ci.yml` | Fast Linux-safe source, publication-policy, privacy, and deterministic secret guards |
| Buildkite | `.buildkite/pipeline.yml` | Authoritative Apple Silicon macOS secret scan, `ResponsayCore` tests, generated Xcode project, app test build, and executed `ResponsayMac` tests |

Responsay is a macOS application. Depot must not run Linux Swift compilation as a substitute for AppKit, AVFoundation, Xcode, or native framework validation. The portable Depot job is deliberately small:

```bash
depot ci run --repo xianwei/responsay-macos \
  --org 2wztpgtn69 \
  --workflow .depot/workflows/ci.yml --job guard
```

The explicit repository and organization are required because the retained GitHub archive is not Depot's execution source and the account belongs to more than one Depot organization.

Cursor agents may use `/fix-ci` for the same bounded run-status-diagnose-logs loop. No signing, notarization, release, or provider credentials belong in Depot or Buildkite.

Buildkite uses the hosted `macos-medium` queue and asserts both `Darwin` and `arm64` before doing any work. Its native contract is the repository's existing sequence:

```bash
scripts/ci/public-source-gate.sh
scripts/ci/scan-secrets.sh
scripts/fetch-sherpa-onnx.sh
swift test --package-path Packages/ResponsayCore
xcodegen generate
xcodebuild build-for-testing -scheme ResponsayMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -scheme ResponsayMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

The hosted macOS queue must not be purchased or renewed automatically. If Buildkite requires a paid plan, keep the pipeline unactivated and report the payment boundary.

## Pull requests and default-branch rules

Everything lands through an Origin pull request. `main` is configured for merge commits only, an up-to-date branch, automatic deletion of the merged source branch, and the exact required checks reported by Depot and Buildkite. Force pushes and branch deletion are blocked.

Cursor Origin Early Beta can report its own server-created merge commit as a direct push. The repository rules therefore enforce the PR and required-check path without enabling a rule that rejects Origin's merge commit itself. This implementation detail does not authorize users or agents to push directly to `main`.

After the first real run, add the exact reported check names to the ruleset; a missing or skipped check is never green. Before merging, re-fetch and confirm `origin/main` is an ancestor of the branch, every local and remote gate is green, and review threads are resolved. Merge with a merge commit, then verify the resulting remote `main` object and ancestry rather than trusting only the web UI.

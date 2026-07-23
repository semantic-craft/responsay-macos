# Contributing

## Source of truth

This repository is the canonical development repository for:

- `macOS/`
- `Tests/ResponsayMacTests/`
- the public files under `Packages/ResponsayCore/`

The Windows implementation lives in `responsay-windows` and is not synchronized with this tree. An internal product repository may consume a pinned ResponsayCore revision and keep private iOS, research, signing, and release material, but it must not become a second editing source for the paths above.

Changes flow from this repository to internal consumers. Do not copy an internal working tree wholesale into this repository.

## Development workflow

1. Start macOS and ResponsayCore changes in this repository.
2. Keep credentials, signing identities, private fixtures, captured pages, user data, and internal release material out of the change.
3. Regenerate the Xcode project from `project.yml`; do not commit `Responsay.xcodeproj`.
4. Run the relevant tests before opening a pull request.

```bash
scripts/ci/public-source-gate.sh
scripts/ci/scan-secrets.sh
swift test --package-path Packages/ResponsayCore
scripts/fetch-sherpa-onnx.sh
xcodegen generate
xcodebuild build-for-testing -scheme ResponsayMac -destination 'platform=macOS'
```

Microphone, accessibility, global-hotkey, insertion, Keychain, and screen-recording behavior still requires a real-Mac check.

## Security gate

Maintainers run Gitleaks and TruffleHog against the Git history and worktree before publication and after security-sensitive changes. Raw scanner reports remain outside the repository because they can contain candidate secrets or identifying paths.

The public-source gate intentionally accepts only the documented public paths. Adding a new top-level file, workflow, script, or documentation path therefore requires an explicit review and allowlist change; this is a publication boundary, not a general lint rule.

Never commit API keys, passwords, signing private keys, provisioning profiles, notarization credentials, real user transcripts, or captured private documents. Test credentials must be unmistakably synthetic.

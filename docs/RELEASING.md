# Releasing Responsay for macOS

The public repository owns the public macOS release. Builds run on GitHub's hosted `macos-26` runner; no maintainer machine or internal repository is required.

## Trust boundary

The workflow has two jobs:

1. `preflight` checks out the requested tag, proves that it belongs to `main`, enforces the public path allowlist, runs Gitleaks and TruffleHog, tests `ResponsayCore`, and performs an unsigned macOS build. It has read-only repository access and no release secrets.
2. `release` starts only after preflight succeeds and the `public-release` GitHub Environment approves deployment. It receives the signing and notarization secrets, builds the same tag, signs and notarizes the app and DMG, then creates the GitHub Release.

Raw scanner reports and decoded key material live only in a mode-restricted runner temporary directory. The release driver deletes the temporary keychain, certificate, API key, raw notarization replies, build logs, and optional Sparkle private key input when the job exits. None are uploaded as artifacts.

## One-time GitHub setup

Create an Environment named `public-release`, add a required maintainer reviewer, restrict deployment to the protected release branch, and store these as **Environment secrets**, not repository variables or files:

| Secret | Purpose |
|---|---|
| `RESPONSAY_DEVELOPER_ID_P12_BASE64` | Base64 of the Developer ID Application certificate and private key exported as PKCS#12 |
| `RESPONSAY_DEVELOPER_ID_P12_PASSWORD` | Password protecting that PKCS#12 file |
| `RESPONSAY_APPLE_TEAM_ID` | Team owning the Developer ID certificate |
| `RESPONSAY_ASC_KEY_P8_BASE64` | Base64 of an App Store Connect **team API key** `.p8` file used by `notarytool` |
| `RESPONSAY_ASC_KEY_ID` | App Store Connect API key ID |
| `RESPONSAY_ASC_ISSUER_ID` | App Store Connect API issuer ID |
| `RESPONSAY_SPARKLE_ED_KEY_BASE64` | Optional: base64 of the Sparkle EdDSA private-key file |

Use a narrowly scoped App Store Connect team key and revoke or rotate it independently of the source repository. Never paste secret values into an issue, pull request, Actions log, commit, or local shell history.

The repository's Actions workflow permission should remain read-only by default. Only the `release` job requests `contents: write`, through its short-lived `GITHUB_TOKEN`, to create the GitHub Release.

## Release procedure

1. Merge the release change to `main`. Confirm Public source CI is green.
2. Confirm `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` are correct.
3. Create and push an immutable tag matching the version, for example `v1.5.8`.
4. Run **Release macOS** from GitHub Actions, enter the existing tag, and keep `draft` enabled for the first attempt.
5. Review and approve the `public-release` Environment deployment.
6. Download the DMG from the draft release, verify its checksum and Gatekeeper behavior on a clean Mac, then publish the draft.

The release contains the notarized DMG and SHA-256 checksum. When the optional Sparkle key is configured it also contains a signed `appcast.xml`. That file must still be deployed to the HTTPS URL configured by `SUFeedURL`; uploading it only as a GitHub Release asset does not update the live feed.

If a secret scan, tag check, signature check, notarization, stapling, or Gatekeeper assessment fails, the workflow stops before publication. Do not bypass the gate; fix the source or credential state and run the workflow again.

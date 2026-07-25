# Releasing Responsay for macOS

There are two ways to cut a release, and they share one script. A local release signs with
the certificate already in the maintainer's login keychain. A hosted release runs on
GitHub's `macos-26` runner, which has no keychain, so it receives the same material as
environment secrets instead.

Local is the simpler path and the default: `scripts/release-macos.sh` uses it whenever no
signing secrets are present in the environment.

## Network prerequisite

`notarytool` splits its traffic: status queries go to `appstoreconnect.apple.com`, but the
upload itself goes to **Amazon S3**. Behind a proxy that routes `amazonaws.com` poorly, the
queries succeed and every upload fails with `HTTPClientError.connectTimeout` — and a
partially registered submission then sits at `In Progress` forever, with no log to read.

Check before releasing:

```bash
curl -o /dev/null -sS -w "%{http_code}\n" --max-time 15 https://s3.amazonaws.com/
```

Any real HTTP status (`307`, `403`, …) is fine. `000` means the connection failed; fix the
proxy rule — for example `DOMAIN-SUFFIX,amazonaws.com,PROXY` — before going further.

## Local release

Credentials come from one of two places. An App Store Connect API key is a plain file, so
it cannot disappear mid-run; a keychain profile is more convenient but has been observed
vanishing from the login keychain during a long release.

With an API key (preferred):

```bash
RESPONSAY_ASC_KEY_PATH=~/path/AuthKey_XXXXXXXXXX.p8 \
RESPONSAY_ASC_KEY_ID=XXXXXXXXXX \
RESPONSAY_ASC_ISSUER_ID=<issuer-uuid> \
scripts/release-macos.sh v1.5.9
```

Create the key under App Store Connect → Users and Access → Integrations; the issuer UUID
is on the same page. Or, with a keychain profile stored once:

```bash
xcrun notarytool store-credentials "responsay-notary" --apple-id <apple-id> --team-id <team-id>
scripts/release-macos.sh v1.5.9
```

Omit `--password`; the tool prompts for it, keeping it out of shell history. The Apple ID
must belong to the team that owns the Developer ID certificate.

Either way the script finds the `Developer ID Application` identity in the login keychain,
reads the team from it, builds, signs every nested bundle from the inside out, notarizes,
staples, verifies with Gatekeeper, writes the DMG and its checksum to `build/release/`, and
signs a Sparkle `appcast.xml` with the EdDSA key in the keychain. Nothing is exported and
no secret is configured anywhere.

## Publishing what the script produced

The build is not the release. Three things have to happen afterwards, and until the last
one lands no installed copy learns that an update exists.

1. Create the release in **this repository** for that tag and upload the DMG and its
   `.sha256`. Download it back and confirm the size and checksum match the appcast.
   Releases used to be published from `responsay-releases`; that repository only holds the
   history now, and nothing new goes there.
2. Add the new `<item>` to `public/appcast.xml` in the `responsay-site` repository. Insert
   it above the existing items rather than replacing the file: `generate_appcast` prunes
   entries whose DMG is not in the working directory, which would silently drop the
   published history.
3. Deploy that site. **Its Cloudflare Pages project has no Git provider**, so pushing the
   commit changes nothing on its own:

```bash
npm run build && npx wrangler pages deploy dist --project-name responsay --branch main
```

Then confirm the live feed actually moved:

```bash
curl -sS https://responsay.com/appcast.xml | grep -m1 -A2 '<item>'
```

## Hosted release

Use this when the release should not depend on a maintainer's machine. It needs the
secrets below and is otherwise the same build.

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

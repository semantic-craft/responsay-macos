# Releasing Responsay for macOS

There is one way to cut a release: `scripts/release-macos.sh`, run on a maintainer's Mac.
It signs with the `Developer ID Application` certificate already in the login keychain and
signs the Sparkle feed with the EdDSA key `generate_keys` stored there. Nothing is
exported, and no signing material exists outside that machine.

This repository's root `appcast.xml` is the canonical Sparkle feed. New builds read it from
the repository's stable raw `main` URL. The old `https://responsay.com/appcast.xml` URL is a
compatibility redirect for already-installed builds; cutting a release does not require a
site-repository change or deployment.

A GitHub-hosted release path used to exist alongside this one. It was removed: it had never
completed a release, and it had no step that updated the live Sparkle feed, so following it
produced a GitHub Release that no installed copy would ever learn about.

The steps below are the whole procedure, in order. **Until step 6's appcast pull request
lands, no installed copy knows an update exists.**

## Before you start

`notarytool` splits its traffic: status queries go to `appstoreconnect.apple.com`, but the
upload itself goes to **Amazon S3**. Behind a proxy that routes `amazonaws.com` poorly, the
queries succeed and every upload fails with `HTTPClientError.connectTimeout` — and a
partially registered submission then sits at `In Progress` forever, with no log to read.

```bash
curl -o /dev/null -sS -w "%{http_code}\n" --max-time 15 https://s3.amazonaws.com/
```

Any real HTTP status (`307`, `403`, …) is fine. `000` means the connection failed; fix the
proxy rule — for example `DOMAIN-SUFFIX,amazonaws.com,PROXY` — before going further.

Notarization credentials come from one of two places. An App Store Connect API key is a
plain file, so it cannot disappear mid-run; a keychain profile is more convenient but has
been observed vanishing from the login keychain during a long release. Store a profile once
with:

```bash
xcrun notarytool store-credentials "responsay-notary" --apple-id <apple-id> --team-id <team-id>
```

Omit `--password`; the tool prompts for it, keeping it out of shell history. The Apple ID
must belong to the team that owns the Developer ID certificate.

## 1. Bump the version

Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`. Open a pull
request and merge it once CI is green.

Nothing enforces either half automatically. The `main` ruleset requires a pull request and
blocks unresolved review threads, but it has no required checks or approval requirement.
The pull request is the review surface; CI is an additional safety signal, not a substitute
for the local test suites below.

Run both suites locally before tagging regardless of what CI says, because CI does not cover
the same ground:

```bash
swift test --package-path Packages/ResponsayCore
xcodebuild test -scheme ResponsayMac -destination 'platform=macOS'
```

The workflow only does `build-for-testing` for the macOS target, so those tests **compile**
in CI and never **run** there — a failure in them leaves CI green. Its `macos-26` runners
also queue for tens of minutes when GitHub is short on them, which is the usual reason a
release ends up merged with CI still pending.

## 2. Tag the merge commit

```bash
git tag -a v1.5.10 -m "Responsay 1.5.10 (build 143)" <merge-sha>
git push origin v1.5.10
```

The tag must match `MARKETING_VERSION`; the script refuses otherwise. Confirm the tag is on
`main` before continuing.

## 3. Build, sign, and notarize

From a clean checkout of that tag:

```bash
scripts/release-macos.sh v1.5.10
```

With an App Store Connect API key instead of the keychain profile:

```bash
RESPONSAY_ASC_KEY_PATH=~/path/AuthKey_XXXXXXXXXX.p8 \
RESPONSAY_ASC_KEY_ID=XXXXXXXXXX \
RESPONSAY_ASC_ISSUER_ID=<issuer-uuid> \
scripts/release-macos.sh v1.5.10
```

Create the key under App Store Connect → Users and Access → Integrations; the issuer UUID
is on the same page.

The script builds, signs every nested bundle from the inside out, notarizes the app and the
DMG separately, staples both, verifies with Gatekeeper, and writes three files to
`build/release/`: `Responsay.dmg`, `Responsay.dmg.sha256`, and a signed `appcast.xml`
holding the single new `<item>`.

It refuses to start if any of those three already exist. Clear `build/release/` between
attempts rather than working around the check.

**The DMG filename is fixed on purpose.** The site's download button is a permanent
redirect to `releases/latest/download/Responsay.dmg`, which GitHub resolves by filename; a
versioned name 404s that link.

## 4. Create the GitHub Release

In **this repository**, for that tag, with the DMG and its `.sha256` attached. Releases used
to be published from `responsay-releases`; that repository is gone and nothing new goes
there.

Match the existing release-note convention: a one-line summary of what changed, then a
`SHA-256:` line carrying the checksum.

## 5. Verify what you published

```bash
curl -sSL -o /tmp/verify.dmg https://github.com/semantic-craft/responsay-macos/releases/latest/download/Responsay.dmg
shasum -a 256 /tmp/verify.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 /tmp/verify.dmg
```

The checksum must match the published `.sha256`, and Gatekeeper must report
`accepted` / `source=Notarized Developer ID`. The `releases/latest/download/` form must
resolve — the site's redirect depends on it.

## 6. Add the appcast item

Copy the `<item>` block from `build/release/appcast.xml` into this repository's root
`appcast.xml`, **inserted above the existing items**, and merge it through a pull request.
The feed is served from `main`, so the merge is what publishes the update.

Do not re-run `generate_appcast` against that file: it prunes entries whose DMG is not in
the working directory, which silently drops the published history. Confirm the diff is pure
insertion — `git diff --numstat` should show zero deletions — and that the item count grew
by exactly one.

## 7. Confirm both feed URLs moved

```bash
curl -sSL -o /dev/null -w "%{http_code} %{size_download}\n" https://responsay.com/Responsay.dmg
curl -sS -o /dev/null -w "%{http_code} %{redirect_url}\n" https://responsay.com/appcast.xml
curl -fsSL -o /tmp/appcast-canonical.xml \
  https://raw.githubusercontent.com/semantic-craft/responsay-macos/main/appcast.xml
curl -fsSL -o /tmp/appcast-legacy.xml https://responsay.com/appcast.xml
cmp appcast.xml /tmp/appcast-canonical.xml
cmp appcast.xml /tmp/appcast-legacy.xml
grep -m1 -A2 '<item>' /tmp/appcast-canonical.xml
```

The download must return `200` with the DMG's real byte count, and the newest appcast item
must be the version you just cut. Both `cmp` commands must be silent: new builds fetch the
canonical URL, while versions through 1.7.0 keep polling the legacy redirect. GitHub's raw
endpoint currently advertises a five-minute cache lifetime, so allow for that edge-cache
window before treating a just-merged stale response as a failure. Once both paths expose
the same newest item, installed copies can learn about the update.

## If something fails

Signature, notarization, stapling, and Gatekeeper failures all stop the script before it
writes anything publishable. Fix the source or the credential state and run it again; do
not work around a check. Sanitized diagnostics are printed on failure — the script redacts
home paths, signing identity hashes, and team IDs.

A notarization submission that stalls at `In Progress` with no log is almost always the
proxy problem described above, not an Apple queue delay.

## Local debug signing

This is not part of cutting a release, but it is the other place signing metadata belongs.

Debug builds are ad-hoc signed by default so a clone with no certificates still builds.
Ad-hoc code has no certificate to anchor to, so its designated requirement is a literal
`cdhash` — the executable's own hash, different on every build. Keychain ACLs match an app
by that requirement, so every rebuild looks like a new app and macOS asks for the login
keychain password again; "Always Allow" only ever covers the build you clicked it on.

If you hold a certificate, create `macOS/Signing.local.xcconfig` (gitignored,
`#include?`-ed by `macOS/Signing.xcconfig`). All three settings are required — an identity
alone fails with *"requires selecting either a development team or a provisioning
profile"*:

```
CODE_SIGN_IDENTITY = Developer ID Application
CODE_SIGN_STYLE = Manual
DEVELOPMENT_TEAM = <your-team-id>
```

Your team id is the parenthesised code in `security find-identity -v -p codesigning`.
Leave it out of any tracked file: the gate rejects a literal ten-character team id
everywhere, this document included.

The requirement then reads `anchor apple generic and identifier "…" and certificate
leaf[subject.OU] = <team>`, which no longer mentions the binary, so it holds across
rebuilds. Expect one last prompt after switching: the existing ACL entries still name the
old `cdhash`. Verify with `codesign -d -r- <app>` — the line must not contain `cdhash`.

Keep these settings out of `project.yml`: a target build setting outranks the target's
xcconfig and would silence the local override. They are also why the leak scanner allows
signing metadata in this file and refuses it elsewhere.

# Releasing Responsay for macOS

There is one way to cut a release: `scripts/release-macos.sh`, run on a maintainer's Mac.
It signs with the `Developer ID Application` certificate already in the login keychain and
signs the Sparkle feed with the EdDSA key `generate_keys` stored there. Nothing is
exported, and no signing material exists outside that machine.

Development, review, and version-bump pull requests live on GitHub. GitHub Actions checks are required before merging; see `docs/operations/ci.md`.

This document describes the proposed R2 distribution workflow. Complete the migration gate below before releasing a build that changes the installed update URL. GitHub remains the primary source repository.

This repository's root `appcast.xml` is the canonical Sparkle feed. New builds read
the deployed copy from `https://updates.responsay.com/appcast.xml`. Signed and notarized
artifacts live in the `responsay-updates` Cloudflare R2 bucket; source code and signing keys
never go there. `https://responsay.com/Responsay.dmg` and the legacy
`https://responsay.com/appcast.xml` path must redirect to the R2 custom domain before
cutover is complete.

The steps below are the whole procedure, in order. **Until the final appcast upload in step
5 succeeds, no installed copy knows an update exists.**

## Draft implementation blocker

Do not execute this proposed cutover sequence yet. Existing clients still poll GitHub Raw,
so merging a new root appcast item publishes it to those clients immediately. The current
publisher uploads artifacts and the R2 feed in one invocation; before activation, provide and
test an artifacts-only phase, verify its immutable DMG URL, then merge the transition item on
GitHub, and only then publish the R2 feed. The numbered steps below require that split before
they can be used for a real transition release.

## Before you start

One-time R2 setup:

1. Create the `responsay-updates` bucket in the Cloudflare account that owns
   `responsay.com`.
2. Connect `updates.responsay.com` as the bucket's production custom domain. Do not enable
   Cloudflare Access on this hostname: Sparkle needs anonymous HTTPS reads.
3. Authenticate Wrangler with an account that can write this bucket. The publisher invokes
   the pinned official CLI through `npx`; keep its OAuth token in Wrangler's credential store
   and never add it to this repository.

The public bucket contains only DMGs, checksums, and the appcast. The Sparkle EdDSA private
key remains in the maintainer Mac's login keychain.

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
xcrun notarytool store-credentials "xw-notary" --apple-id <apple-id> --team-id <team-id>
```

Omit `--password`; the tool prompts for it, keeping it out of shell history. The Apple ID
must belong to the team that owns the Developer ID certificate.

## 1. Bump the version

Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`. Open a pull
request and merge it once CI is green.

Nothing enforces either half automatically. The GitHub `main` rules require a pull request,
an up-to-date branch, and successful GitHub Actions checks. The pull request is the
review surface; remote CI is an additional safety signal, not a substitute for the local
test suites below.

Run both suites locally at the exact merge commit before tagging. GitHub Actions runs the same
native tests on a clean hosted Mac, but the release still depends on the maintainer Mac's
signing, notarization, and final artifact checks:

```bash
swift test --package-path Packages/ResponsayCore
xcodebuild test -scheme ResponsayMac -destination 'platform=macOS'
```

GitHub Actions must report both `build-for-testing` and executed `ResponsayMac` tests green. A
queued, skipped, missing, or still-running hosted-macOS check is not release evidence.

## 2. Tag the merge commit on GitHub

```bash
git tag -a v1.5.10 -m "Responsay 1.5.10 (build 143)" <merge-sha>
git push origin v1.5.10
```

The tag must match `MARKETING_VERSION`; the script refuses otherwise. Confirm the tag is on
GitHub `origin/main` before continuing. R2 stores release artifacts, not source code.

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

**The local DMG filename is fixed on purpose.** The publisher stores it twice: an immutable
`releases/<tag>/Responsay.dmg` object for Sparkle and a short-cache `Responsay.dmg` object
for the website's stable download URL.

## 4. Add the appcast item

Copy the `<item>` block from `build/release/appcast.xml` into this repository's root
`appcast.xml`, **inserted above the existing items**, and merge it through a GitHub pull
request only after its immutable DMG and checksum are publicly available and verified.
This merge immediately advertises the update to clients polling GitHub Raw; the unsplit
publisher below is not yet sufficient to implement that ordering.

Do not re-run `generate_appcast` against that file: it prunes entries whose DMG is not in
the working directory, which silently drops the published history. Confirm the diff is pure
insertion — `git diff --numstat` should show zero deletions — and that the item count grew
by exactly one.

## 5. Publish the verified artifacts and feed

From the verified release workspace after its root `appcast.xml` includes the reviewed new
item:

```bash
scripts/publish-update-r2.sh v1.5.10
```

The publisher validates the local checksum, notarization ticket, and Gatekeeper assessment;
uploads the immutable versioned DMG and checksum; downloads the versioned DMG and validates
it again; refreshes the stable website download objects; and uploads `appcast.xml` last. It
then verifies that the live feed exactly matches this repository.

The default bucket is `responsay-updates`. Staging may override
`RESPONSAY_R2_BUCKET`, `RESPONSAY_UPDATE_BASE_URL`, or `RESPONSAY_WRANGLER`; production
releases use the defaults.

## 6. Confirm the public and compatibility URLs

```bash
curl -sSL -o /dev/null -w "%{http_code} %{size_download}\n" https://updates.responsay.com/Responsay.dmg
curl -fsSL https://updates.responsay.com/appcast.xml | grep -m1 -A3 '<item>'
curl -sSIL https://responsay.com/Responsay.dmg | grep -i '^location:'
curl -sSIL https://responsay.com/appcast.xml | grep -i '^location:'
```

Both Responsay URLs must redirect to `updates.responsay.com`; the update host must return
the real DMG and the new feed item. Versions that already use the Responsay compatibility
feed therefore continue to update through the new distribution host.

## GitHub-to-R2 migration gate

Versions pointing directly at GitHub Raw need a transition release through the existing
GitHub feed. Prove two hops on a real installed app: current public release → transition
release → R2-hosted test release. Verify the R2 custom domain, signed DMG, feed, and website
redirects before completing the cutover. Keep the GitHub repository and legacy feed public;
R2 distribution does not change GitHub's role as the primary source repository. Publish the
reviewed transition appcast through a GitHub PR. No source mirror or privacy change is needed.

## If something fails

Signature, notarization, stapling, and Gatekeeper failures stop the build before it writes
anything publishable. Upload or live-download verification failures stop publication before
the appcast is uploaded. Fix the source, credential, DNS, or object state and rerun the
failed phase; do not work around a check. Build diagnostics redact home paths, signing
identity hashes, and team IDs.

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

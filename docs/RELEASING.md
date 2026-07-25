# Releasing Responsay for macOS

There is one way to cut a release: `scripts/release-macos.sh`, run on a maintainer's Mac.
It signs with the `Developer ID Application` certificate already in the login keychain and
signs the Sparkle feed with the EdDSA key `generate_keys` stored there. Nothing is
exported, and no signing material exists outside that machine.

A GitHub-hosted release path used to exist alongside this one. It was removed: it had never
completed a release, and it had no step that updated the live Sparkle feed, so following it
produced a GitHub Release that no installed copy would ever learn about.

The steps below are the whole procedure, in order. **Until step 8 lands, no installed copy
knows an update exists.**

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
request — `main` is protected and requires one — and merge it once CI is green.

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

Copy the `<item>` block from `build/release/appcast.xml` into `public/appcast.xml` in the
`responsay-site` repository, **inserted above the existing items**.

Do not re-run `generate_appcast` against that file: it prunes entries whose DMG is not in
the working directory, which silently drops the published history. Confirm the diff is pure
insertion — `git diff --numstat` should show zero deletions — and that the item count grew
by exactly one.

## 7. Deploy the site

**Its Cloudflare Pages project has no Git provider**, so pushing the commit changes nothing
on its own:

```bash
npm run build && npx wrangler pages deploy dist --project-name responsay --branch main
```

`git fetch` and confirm you are level with the remote **before** building. That repository
also carries an unrelated product's release pages, so the remote can move between your
build and your deploy. If a push is rejected, rebase and **rebuild** — deploying a `dist`
built from the older base rolls back whatever landed in between.

## 8. Confirm the live feed moved

```bash
curl -sSL -o /dev/null -w "%{http_code} %{size_download}\n" https://responsay.com/Responsay.dmg
curl -sS https://responsay.com/appcast.xml | grep -m1 -A2 '<item>'
```

The download must return `200` with the DMG's real byte count, and the newest appcast item
must be the version you just cut. `SUFeedURL` itself never changes — Sparkle reads the
newest item's `enclosure`, so this is the moment installed copies learn about the update.

## If something fails

Signature, notarization, stapling, and Gatekeeper failures all stop the script before it
writes anything publishable. Fix the source or the credential state and run it again; do
not work around a check. Sanitized diagnostics are printed on failure — the script redacts
home paths, signing identity hashes, and team IDs.

A notarization submission that stalls at `In Progress` with no log is almost always the
proxy problem described above, not an Apple queue delay.

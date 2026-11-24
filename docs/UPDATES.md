# In-app updates

Airpisode updates itself with [Sparkle 2](https://sparkle-project.org) (pinned to
2.10.1 in `project.yml`). Sparkle owns the update UI: it shows the new version and its
release notes, downloads with progress, and offers install-now/later and relaunch.
The app adds two entry points — **Airpisode ▸ Check for Updates…** (⇧⌘U) and a section
in **Settings ▸ About** — plus a daily automatic check.

Everything Sparkle needs comes from `Info.plist`:

| Key | Value | Why |
| --- | --- | --- |
| `SUFeedURL` | `$(SU_FEED_URL)` | Where the appcast lives. Must be HTTPS. |
| `SUPublicEDKey` | `$(SU_PUBLIC_ED_KEY)` | EdDSA key that signs the appcast and every archive. |
| `SUEnableAutomaticChecks` | `true` | Daily background checks; Sparkle stores the user's own choice. |
| `SUScheduledCheckInterval` | `86400` | One check per day. |
| `SUAutomaticallyUpdate` | `false` | Never install silently; the user confirms. |
| `SUAllowsAutomaticUpdates` | `true` | The user may opt into automatic installation. |
| `SUVerifyUpdateBeforeExtraction` | `true` | Verify the archive signature before unpacking it. |
| `SURequireSignedFeed` | `true` | Reject an appcast without a valid signature. |

`SU_FEED_URL` and `SU_PUBLIC_ED_KEY` are build settings. `Airpisode/Config/App.xcconfig`
defines them as empty and then optionally includes `Airpisode/Config/Sparkle.local.xcconfig`,
which is git-ignored. **A build without that file runs with updates switched off** — the
About pane says so instead of showing a button that cannot work — and it never points at
a placeholder host.

## One-time setup

### 1. Signing

Sparkle trusts an update because the appcast and the archive carry an EdDSA signature
that verifies against `SUPublicEDKey`. It does not require an Apple Developer ID.
Airpisode's releases are ad-hoc signed, which Sparkle accepts, so updates install on any
Mac that can run the app.

A Developer ID certificate and notarization are optional: they remove the Gatekeeper
warning users see the first time they open a freshly downloaded copy. `build-dmg.sh`
uses them automatically when `AIRPISODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM` are set,
and signs ad-hoc otherwise.

### 2. Update keys

The repository already contains a public key and feed URL in
`Airpisode/Config/App.xcconfig`. The matching private key lives in the release machine's
login Keychain (account `ed25519`) and is what `make-appcast.sh` signs with. Only if you
need to replace it:

```bash
Scripts/fetch-sparkle-tools.sh
.build/sparkle-tools/bin/generate_keys
```

`generate_keys` stores the new private key and prints the public key. Put the public key
in `App.xcconfig` as `SU_PUBLIC_ED_KEY`; you do not need to keep it secret.

Back the private key up somewhere safe — losing it means every installed copy has to be
replaced by hand:

```bash
.build/sparkle-tools/bin/generate_keys -x ~/airpisode-ed-key.txt
```

Keep that file out of the repo. Rotating the key requires shipping a build signed with
the *old* key once more, so do it rarely.

### 3. Local overrides (optional)

`App.xcconfig` values are enough to build. To point a checkout at a different feed while
testing, copy the example and edit it; the file is git-ignored and overrides the defaults:

```bash
cp Airpisode/Config/Sparkle.local.xcconfig.example Airpisode/Config/Sparkle.local.xcconfig
```

xcconfig treats `//` as a comment, so a URL is written with an empty `$()` between the
slashes:

```
SU_FEED_URL = https:/$()/example.com/appcast.xml
SU_PUBLIC_ED_KEY = <the base64 public key>
```

`releases/latest/download/appcast.xml` always serves the appcast from the newest
release, so releases never need to change the committed URL.

### 4. Check it locally

```bash
xcodegen generate
xcodebuild -project Airpisode.xcodeproj -scheme Airpisode -configuration Debug build
```

Settings ▸ About should now show **Check for updates automatically** and a working
**Check for Updates…** button.

## Publishing a release

1. Bump the marketing version once, in `project.yml`:

   ```yaml
   MARKETING_VERSION: "3.0.4"
   ```

2. Write the release notes. `generate_appcast` embeds a file with the same base name as
   the DMG, so create `dist/Airpisode-3.0.4.md` *after* building (or pass `--embed-release-notes`
   with a matching name; the script already does).

3. Build the disk image:

   ```bash
   ./Scripts/build-dmg.sh
   ```

   That ad-hoc signs, which is enough for Sparkle. To also remove the Gatekeeper warning,
   sign with a Developer ID and notarize:

   ```bash
   AIRPISODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
   DEVELOPMENT_TEAM=TEAMID \
   NOTARIZE=1 \
   ./Scripts/build-dmg.sh
   ```

   `BUILD` defaults to a UTC timestamp, which is what Sparkle compares; override it with
   an integer if you prefer. Either way it must increase on every release, and it must
   differ from the previous release even when the marketing version is unchanged.

4. Generate the signed appcast:

   ```bash
   ./Scripts/make-appcast.sh
   ```

   This uses the Keychain key by default, or `SPARKLE_ED_KEY_FILE` / `SPARKLE_ED_PRIVATE_KEY`
   in CI. It writes `dist/appcast.xml`. **There must be no warning about `SUPublicEDKey`
   not matching the signing key** — that warning means installed apps will reject the
   update.

5. Publish the release:

   ```bash
   gh release create v0.3.0 \
     dist/Airpisode-0.3.0.dmg dist/appcast.xml \
     --title "Airpisode 0.3.0" --notes-file dist/Airpisode-0.3.0.md
   ```

   The DMG must keep the exact name that appears in the appcast's `enclosure` URL.

6. Verify before announcing:

   ```bash
   .build/sparkle-tools/bin/sign_update --verify dist/appcast.xml
   grep -E "sparkle:version|enclosure" dist/appcast.xml
   ```

   Then install the *previous* release, open it, choose Check for Updates…, and confirm
   the new version is offered, downloads, installs, and relaunches.

## GitHub Actions

`.github/workflows/release.yml` runs on a `v*` tag: tests, DMG, appcast, release.

Secrets to add in the repository settings:

| Secret | Purpose |
| --- | --- |
| `SPARKLE_ED_PRIVATE_KEY` | The exported private key file's contents. |
| `DEVELOPER_ID_APPLICATION` | Certificate name, e.g. `Developer ID Application: Your Name (TEAMID)`. |
| `DEVELOPMENT_TEAM` | Ten-character team ID. |
| `BUILD_CERTIFICATE_BASE64`, `BUILD_CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD` | The `.p12` certificate, base64-encoded, and its passwords. |
| `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | Notarization. |

Without `SPARKLE_ED_PRIVATE_KEY` the appcast step is skipped, and the workflow publishes
only the DMG, as it does today. Without the signing secrets the DMG is ad-hoc signed,
which is fine to share but cannot update itself.

## Security model

- **HTTPS only.** `UpdateConfiguration` refuses a feed URL that is not `https`, so a
  misbuilt app fails closed instead of trusting cleartext.
- **Signed feed and archives.** With `SUPublicEDKey` set and `SURequireSignedFeed = true`,
  Sparkle rejects a modified appcast, a missing signature, or an archive that does not
  match its signature.
- **Verify before extraction.** The archive signature is checked before it is unpacked.
- **Signed archives are the trust anchor.** Every archive must carry an EdDSA signature
  that verifies against `SUPublicEDKey`, and the app inside it must have an intact code
  signature (ad-hoc is fine). The Developer ID team check only applies as a fallback
  when an EdDSA signature cannot be verified.
- **Hardened runtime.** `build-dmg.sh` enables it for Developer ID builds, as notarization
  requires.
- **No secrets in the app.** The public key is not sensitive; the private key never enters
  the bundle, the repo, or CI logs.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| About says "This build has no update feed configured" | `Sparkle.local.xcconfig` is missing, or the URL/key did not resolve. Run `xcodebuild -showBuildSettings \| grep SU_`. |
| `SU_FEED_URL` shows only `https:` | The `//` was eaten as a comment. Write `https:/$()/host/path`. |
| "You're up to date" on every launch | `sparkle:version` in the appcast does not exceed the running app's `CFBundleVersion`. |
| Update downloads, then fails to install | The app bundle inside the DMG is unsigned or its code signature is corrupted, or Sparkle cannot write to /Applications. |
| "The update is improperly signed" | Appcast and archive were signed with a key that does not match the app's `SUPublicEDKey`. |
| Check errors while offline | Expected; Sparkle reports a network error in its own dialog and never installs anything. Automatic checks retry on the next interval. |
| Updates never appear to check in development | The debug placeholder host 404s by design. Point `SU_FEED_URL` at a real appcast to test detection. |

## Not done here

These need credentials or infrastructure that this repository does not have:

- the first published release containing `appcast.xml` (the feed URL is already set),
- a Developer ID certificate and notarization secrets, only if you want to drop the
  first-launch Gatekeeper warning.

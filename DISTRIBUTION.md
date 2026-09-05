# Distribution and updates

## Current signing status

AirCiller uses an ad hoc signature for local builds. The project does not assume an Apple Developer Program membership and does not run Developer ID signing, Hardened Runtime, notarization, stapling, or `notarytool`.

This has one visible consequence. A Mac that downloads AirCiller for the first time may block the first launch until the user confirms it through macOS. Sparkle cannot remove that first-install Gatekeeper step. It can securely deliver later AirCiller updates after the initial copy is trusted.

Developer ID and notarization remain a future distribution improvement. Their absence must never be reported as a successful notarized build.

## Sparkle integration

AirCiller uses the official Sparkle 2.9.6 binary distribution.

| Item | Value |
| --- | --- |
| Release | `2.9.6` |
| Archive | `Sparkle-2.9.6.tar.xz` |
| SHA-256 | `52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192` |
| Source | `https://github.com/sparkle-project/Sparkle/releases/tag/2.9.6` |

The project has no Xcode project or Swift Package Manager application target. `build.sh` compiles the Swift sources directly and assembles the app bundle itself. A package declaration would resolve Sparkle source code, but it would not take care of embedding its framework and helper tools in this custom bundle. The build therefore downloads the official binary archive, verifies its digest, preserves its symlinks, links it, and copies it into `Contents/Frameworks`.

Run this once on a new checkout:

```sh
./Scripts/bootstrap_sparkle.sh
```

The dependency lives under `.build/dependencies` and is not committed. CI performs the same verified download.

## Update policy

- The appcast and release archives must use HTTPS.
- Every archive must carry Sparkle's EdDSA signature.
- The appcast itself is signed because `SURequireSignedFeed` is enabled.
- Archives are verified before extraction because `SUVerifyUpdateBeforeExtraction` is enabled.
- Automatic checks are controlled by Sparkle's own user preference.
- Update checks are postponed during media analysis, preparation, and playback.
- Automatic downloading and installation are disabled. The user confirms each installation.
- The EdDSA private key stays in the maintainer's login Keychain and must never enter Git.
- The public key belongs in `Info.plist` and is safe to publish.

## Bundled playback engine

AirCiller releases include fixed FFmpeg and CPython builds. End users update them only by installing a tested AirCiller release. Settings does not offer separate engine updates.

`Scripts/bootstrap_engine.sh` downloads the pinned archives used for the build, verifies their SHA-256 digests, checks their executable versions, and stages them under `.build/dependencies`. `build.sh` copies the complete engine into the app. The runtime is therefore available on first launch and without internet access.

The current reference archives were built by AirCiller from the sources and checksums recorded in `Scripts/build_managed_components.sh`. The older signed component catalogue remains in the repository so releases 0.10.3 through 0.10.5 can be reproduced and audited. Current builds do not read it.

An engine upgrade is treated as an application change. It requires locked versions, local checks, direct MP4 and HLS/fMP4 validation, and a physical Apple TV test before release. A new upstream version alone is not a reason to update.

The stable appcast URL is `https://github.com/carlosciller/AirCiller/releases/latest/download/appcast.xml`. It resolves to the signed feed attached to the latest GitHub Release. AirCiller validates that this URL uses HTTPS and that its public key decodes to the expected EdDSA length before starting Sparkle.

## One-time key setup

After bootstrapping Sparkle, create the AirCiller signing key once:

```sh
./.build/dependencies/Sparkle-2.9.6/bin/generate_keys --account AirCiller
```

The command stores the private key in the login Keychain and prints the public key. Copy only that public key into `SUPublicEDKey`. Keep an offline backup of the private key outside the repository. Losing this key is especially serious while releases do not share a Developer ID identity.

## Appcast setup

`Distribution/appcast.xml.example` documents the fields. The generated and signed `appcast.xml` is attached to each GitHub Release.

Sparkle's `generate_appcast` tool should create the published XML. It signs the archives and, with AirCiller's current settings, signs the feed too. Do not hand-edit a generated signed feed.

## Release procedure

Before tagging or uploading a new binary, run `Scripts/check.sh` on the candidate and complete the applicable physical matrix in [TESTING.md](TESTING.md). Shared session or server changes affect both playback paths. Record failures and untested cases explicitly; a successful build alone does not pass this gate.

1. Increase `CFBundleShortVersionString` and the numeric `CFBundleVersion`.
2. Update `CHANGELOG.md` and write concise, user-facing notes in `Distribution/ReleaseNotes/<version>.md`. Use `TEMPLATE.md` as the starting point, describe visible outcomes, and omit implementation details.
3. Prepare the pinned engine, build AirCiller, and verify its ad hoc signature:

   ```sh
   ./Scripts/bootstrap_engine.sh
   ./build.sh
   ```
4. Package the app:

   ```sh
   ./Scripts/package_update.sh
   ```

5. Confirm that `package_update.sh` copied the versioned release notes beside the ZIP with the same base filename.
6. Generate and sign the appcast using the real release asset prefix and project link:

   ```sh
   ./.build/dependencies/Sparkle-2.9.6/bin/generate_appcast \
     --account AirCiller \
     --download-url-prefix "__HTTPS_RELEASE_ASSET_PREFIX__/" \
     --link "__PROJECT_URL__" \
     --embed-release-notes \
     --versions "__BUILD_NUMBER__" \
     --maximum-versions 1 \
     .build/releases
   ```

   Each GitHub Release has its own asset prefix, so the published feed contains the latest full update and its deltas only. Older full archives remain available under their original release tags.

7. Verify the signed feed:

   ```sh
   ./.build/dependencies/Sparkle-2.9.6/bin/sign_update \
     --account AirCiller \
     --verify \
     .build/releases/appcast.xml
   ```

8. Upload the ZIP, release notes, and appcast to their final HTTPS locations.
9. Confirm that every URL in the appcast returns the expected file without authentication or redirects to an untrusted host.
10. Use an older AirCiller build to run **Check for Updates…**, download the new archive, install it, relaunch, and confirm the new version.
11. Replace the daily-use copy only after the candidate is accepted and installation is authorized. Keep a rollback copy. The physical matrix must already be complete before publication.

The placeholder values above are documentation markers. They are not valid publication URLs.

## Local checks

```sh
./Scripts/check.sh
./Scripts/audit_distribution.sh .build/AirCiller.app
```

The first command must pass. The distribution audit is expected to report the missing Developer ID, Hardened Runtime, notarization, and Gatekeeper acceptance until those facilities are available.

Sparkle's setup and publishing requirements are documented in its [official integration guide](https://sparkle-project.org/documentation/) and [publishing guide](https://sparkle-project.org/documentation/publishing/).

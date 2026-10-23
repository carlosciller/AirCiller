# Distribution and updates

## Current signing status

AirCiller defaults to an ad hoc signature on a fresh checkout. Development machines can opt into a stable local code-signing identity and the [read-only credential service](Docs/CREDENTIAL_SERVICE.md). A certificate alone does not retain Keychain permission across rebuilt copies on the tested Mac; see the limitation below. Public release builds do not assume an Apple Developer Program membership or run Developer ID signing, notarization, stapling, or `notarytool`. Service-enabled local builds use Hardened Runtime.

This has one visible consequence. A Mac that downloads AirCiller for the first time may block the first launch until the user confirms it through macOS. Sparkle cannot remove that first-install Gatekeeper step. It can securely deliver later AirCiller updates after the initial copy is trusted.

Developer ID and notarization remain a future distribution improvement. Their absence must never be reported as a successful notarized build.

### Deferred Shortcuts integration

Shortcuts remains excluded from the public package under the current signing policy. During the 0.14.1 work, a development-signed candidate registered on the test Mac, but the public ad hoc package failed native registration. The implementation and dated evidence are [preserved separately](Docs/SHORTCUTS.md). That development candidate is not a public-release substitute. Publication must not change the established credential service.

## Stable local signing

After explicitly approving creation of a local identity, run the following with the project's Python runtime:

```sh
python3 Scripts/setup_local_signing.py --create-or-reuse
zsh Scripts/build_credential_service.sh
```

The setup uses the pinned `cryptography` package in `VendorPython`. It creates or reuses **AirCiller Local Development** in the login Keychain and stores only its public certificate fingerprint in the ignored `.local-signing-identity` file. Private key material travels in memory through a pipe to the system importer; it is never written to a temporary file. The imported key permits `/usr/bin/codesign`; setup does not grant access to all applications or change system trust settings.

Both ordinary and playback-check builds use that identity, with distinct application identifiers. Keeping the same certificate and application identifier preserves the designated code requirement. No script requests, stores or forwards the user's Keychain password.

**Keychain limitation verified on 5 September 2026:** the same approved executable can read the AirPlay credential repeatedly without interaction, but a changed executable with the identical designated requirement is denied. The file-based Keychain also checks a partition identifier. Apple's [securityd implementation](https://github.com/apple-oss-distributions/Security/blob/main/securityd/src/clientid.cpp) assigns a code hash to signatures outside its recognized Apple signing categories. The existing item's read-only ACL inspection confirmed accumulated code-hash entries. The credential service keeps its own executable unchanged and authenticates each caller; its validation is documented separately. Do not remove partition protections or add broad access rules.

If configuration exists but the signing key is unavailable, the build fails without falling back to ad hoc signing. Preserve the identity across local rebuilds; removing `.build` does not remove it. An encrypted offline backup can be made separately through Keychain Access. Losing the private key requires a new identity and fresh approvals.

Public release builds keep the existing signing policy. Explicitly set `AIRCILLER_SIGNING_IDENTITY=-` for the release check, which also builds the app. A certificate fingerprint can also be supplied through that variable for other authorized builds. Local signing is not Developer ID, notarization or a replacement for Sparkle's separate EdDSA update key. See Apple's [code-signing guidance](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).

## Sparkle integration

AirCiller uses the official Sparkle 2.9.6 binary distribution.

| Item | Value |
| --- | --- |
| Release | `2.9.6` |
| Archive | `Sparkle-2.9.6.tar.xz` |
| SHA-256 | `52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192` |
| Source | `https://github.com/sparkle-project/Sparkle/releases/tag/2.9.6` |

The project has no Xcode project or Swift Package Manager application target. `build.sh` compiles the Swift sources directly and assembles the app bundle itself. `Scripts/bootstrap_sparkle.sh` downloads and verifies the official binary archive; the build embeds its framework and helpers while preserving their symlinks and signatures. The dependency lives under `.build/dependencies` and is not committed. CI uses the same bootstrap script. See [checkout preparation](CONTRIBUTING.md#prepare-a-checkout) for all required dependencies.

## Update policy

- The appcast and release archives must use HTTPS.
- Every archive must carry Sparkle's EdDSA signature.
- The appcast itself is signed because `SURequireSignedFeed` is enabled.
- Archives are verified before extraction because `SUVerifyUpdateBeforeExtraction` is enabled.
- Automatic checks are controlled by Sparkle's own user preference.
- Update checks are postponed during library imports, media analysis, preparation, and playback.
- Automatic downloading and installation are disabled. The user confirms each installation.
- The EdDSA private key stays in the maintainer's login Keychain and must never enter Git.
- The public key belongs in `Info.plist` and is safe to publish.

## Bundled playback engine

AirCiller releases include fixed FFmpeg and CPython builds. End users update them only by installing a tested AirCiller release. Settings does not offer separate engine updates.

`Scripts/bootstrap_engine.sh` downloads the pinned archives used for the build, verifies their SHA-256 digests, checks their executable versions, and stages them under `.build/dependencies`. `build.sh` copies the runtime into the app, excluding unused pip/ensurepip installers and generated bytecode before signing. The retained runtime files are checked for byte parity with the pinned input. Playback is available on first launch and without internet access; no package installation runs in the app. [Installer packaging](Docs/BUILD_PIP_MAINTENANCE.md).

The current reference archives were built by AirCiller from the sources and checksums recorded in `Scripts/build_managed_components.sh`. They are still downloaded from the `v0.10.3` GitHub Release: `ffmpeg-9.0.1-macos-arm64.zip` and `airplay-python-3.13.15-macos-arm64.zip`. Their older hosting tag does not make them obsolete; retain those pinned assets. The older signed component catalogue remains in the repository so releases 0.10.3 through 0.10.5 can be reproduced and audited. Current builds do not read that catalogue.

An engine upgrade is treated as an application change. It requires locked versions, local checks, direct MP4 and HLS/fMP4 validation, and an Apple TV playback test before release. A new upstream version alone is not a reason to update. Record whether output was digitally captured or physically observed, separately from receiver state.

### Bundle size

Every build measures the signed app before replacing its previous build output. `Scripts/check_bundle_size.py` reports logical file bytes by component and fails above 165,000,000 bytes. Framework symlinks are counted once without following their targets. This measures the app, not download compression, filesystem allocation or prepared-media caches.

Record the current candidate's size report. The 153,923,546-byte measurement from 0.12.3 is a historical baseline, not the current app size. FLAC support reuses the bundled engine. A dependency or asset change that exceeds the budget needs an explicit size review; do not raise the limit automatically or remove runtime files merely to pass it.

## One-time key setup

After bootstrapping Sparkle, create the AirCiller signing key once:

```sh
./.build/dependencies/Sparkle-2.9.6/bin/generate_keys --account AirCiller
```

The command stores the private key in the login Keychain and prints the public key. Copy only that public key into `SUPublicEDKey`. Keep an offline backup of the private key outside the repository. Losing this key is especially serious while releases do not share a Developer ID identity.

## Appcast setup

The stable appcast URL is `https://github.com/carlosciller/AirCiller/releases/latest/download/appcast.xml`. It resolves to the signed feed attached to the latest GitHub Release. AirCiller validates that this URL uses HTTPS and that its public key decodes to the expected EdDSA length before starting Sparkle.

`Distribution/appcast.xml.example` documents the fields. The generated and signed `appcast.xml` is attached to each GitHub Release.

Sparkle's `generate_appcast` tool should create the published XML. It signs the archives and, with AirCiller's current settings, signs the feed too. Do not hand-edit a generated signed feed.

## Release procedure

Publication and installation require authorization in the conversation. Prepare dependencies using [CONTRIBUTING.md](CONTRIBUTING.md#prepare-a-checkout). Keep release evidence tied to the candidate: source commit, version/build, signing configuration, executable and ZIP SHA-256 hashes, size report, applicable playback results, and CI run URLs and commits.

1. Finish the intended changes and increase `CFBundleShortVersionString` and the numeric `CFBundleVersion`.
2. Update `CHANGELOG.md` and write user-facing notes in `Distribution/ReleaseNotes/<version>.md`. Complete the editorial checklist in [TEMPLATE.md](Distribution/ReleaseNotes/TEMPLATE.md): reconcile the release diff, explain usage and compatibility limits, and link the supporting record. Update compatibility and roadmap status where affected. Documentation-only corrections do not require a binary version bump.
3. Review the final diff and identify the clean source revision to be released. Run the full local gate after versioning and release documentation are ready:

   ```sh
   AIRCILLER_SIGNING_IDENTITY=- ./Scripts/check.sh
   ```

   This command includes the strict Swift 6 build, warnings-as-errors, signature-structure verification and bundle-size gate. Package its accepted `.build/AirCiller.app`; do not run a second identical build. Inspect the distribution diagnostics described below. If later changes affect executable inputs, signing or packaging, repeat the affected gates and identify the new artifact. Documentation-only follow-ups require diff/reference checks, not an unchanged binary rebuild.

4. Select the applicable cases under [TESTING.md](TESTING.md), not the entire catalogue. Documentation, pure UI and packaging-only changes do not automatically require an Apple TV session. Shared session or server changes affect both paths; long-pause and extended track/cache tests need their own affected boundary. Record failures and required missing observations explicitly. Carry earlier results forward only with the documented source/runtime/configuration/media comparison. Reused evidence is not a new device run.
5. Verify the required CI result for the reviewed PR and, after authorized merge/tag, the exact merged `main` and tag commits. Each run must complete successfully, but need not rebuild identical inputs: the workflow may explicitly report `reuse` with an originating successful full-check artifact, or `docs` for allowlisted prose. Record the mode, current SHA/run URL and originating evidence URL. Never infer tag acceptance merely from a green PR/main run. Different trees or toolchains, missing/expired evidence or API errors require a full run. Reconcile merge changes and repeat affected local gates. Manual preview runs remain diagnostic, never release evidence. Inspect failures and preserve failed attempts; required pending/failed CI blocks completion. This reuse concerns CI checks only, not signed release artifact identity.
6. Package the accepted app:

   ```sh
   ./Scripts/package_update.sh
   ```

   Confirm the version/build and that the script copied the reviewed versioned release notes beside the ZIP with the same base filename. Record the archive SHA-256 before upload.

7. Generate and sign the appcast using the real release asset prefix and project link:

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

8. Verify the signed feed:

   ```sh
   ./.build/dependencies/Sparkle-2.9.6/bin/sign_update \
     --account AirCiller \
     --verify \
     .build/releases/appcast.xml
   ```

9. Upload the ZIP, release notes and appcast to their final HTTPS locations. Set the GitHub Release body from the reviewed versioned notes and verify its content and links against the changelog and packaged update notes. Historical prose corrections must be identified separately; do not replace an already-published signed feed or archive just to edit wording.
10. Verify the published downloads. Every appcast URL must return the intended file without authentication or redirects to an untrusted host. Compare the downloaded ZIP's SHA-256 with the reviewed local archive; verify the downloaded feed and archive signatures with the pinned Sparkle tools and the public key embedded in the accepted app. Verify the extracted app's code-signature structure and preserved nested signatures. URL availability alone does not establish artifact identity or update acceptance.
11. With installation authorized, preserve a rollback copy and use an older AirCiller build to run **Check for Updates…**, download, install through Sparkle and relaunch. This may use an isolated older copy or the authorized daily-use copy; two installations are not required. Confirm the running app's path, installed version/build, library and preferences. Preserve the update result or relevant logs. Copying the new bundle into place is not a native updater test. If the isolated-copy option is used, replacing the daily-use copy still requires authorization and rollback.

The placeholder values above are documentation markers. They are not valid publication URLs. Report packaged, published and installed as separate outcomes; do not report installation when only the feed, download or update offer has been checked.

Archive/feed signatures, published-byte identity and the authorized installed
version/library/preferences checks remain required for every binary release.
Do not repeat playback merely because installation succeeded. Extended updater
failure/delta scenarios are needed when Sparkle, signing or packaging behavior
changes, not for every unrelated application fix.

## Distribution diagnostics

The release check above verifies signature structure. For the distribution report, inspect the actual signing information and run:

```sh
codesign -d --verbose=4 .build/AirCiller.app
./Scripts/audit_distribution.sh .build/AirCiller.app
```

Under the public ad hoc policy, absent Developer ID, Hardened Runtime, notarization and Gatekeeper acceptance are known distribution limitations. They must be reported, not represented as successful checks. They do not excuse a broken code signature, missing runtime or missing FFmpeg tools; inspect each finding. Do not assume that every nonzero audit result is expected.

The audit verifies Apple's certificate chain and the Developer ID Application certificate extension. A local development certificate does not satisfy this check. Hardened Runtime is read from the CodeDirectory flags. Signature structure, notarization and Gatekeeper acceptance retain their own checks.

Sparkle's setup and publishing requirements are documented in its [official integration guide](https://sparkle-project.org/documentation/) and [publishing guide](https://sparkle-project.org/documentation/publishing/).

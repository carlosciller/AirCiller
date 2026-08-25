# Distribution

## Current status

The public 0.10.1 archive was audited on 25 August 2026.

- The published ZIP matches the SHA-256 value in its release notes.
- The app has an ad hoc signature. It has no Developer ID team identifier.
- Hardened Runtime is not enabled.
- The app has no stapled notarization ticket.
- This Mac has no valid Developer ID Application identity installed.
- The bundled AirPlay modules were built for CPython 3.13 and still use the Python executable recorded when the app was built. In 0.10.1 that path is `/opt/homebrew/bin/python3`.

Version 0.10.1 is therefore suitable for the current local installation, but it is not ready for notarized distribution or automatic installation on another Mac.

## Required order

1. Join the Apple Developer Program and create a Developer ID Application certificate.
2. Package a fixed Python runtime and stop recording a path from the build Mac.
3. Sign every bundled executable and native Python module explicitly.
4. Sign the main app with Developer ID, Hardened Runtime and a secure timestamp.
5. Submit the archive with `notarytool`, staple the ticket and verify it with Gatekeeper.
6. Test the signed build and both playback routes on a clean Mac and a physical Apple TV.
7. Add automatic updates only after the signed release process is repeatable.

Apple documents the current requirements in [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Application updates

The planned updater is Sparkle 2.9.4 or a later version that has been reviewed before integration.

- The appcast will be served over HTTPS from GitHub Pages.
- Release archives will remain on GitHub Releases.
- Archives and the appcast will use Sparkle's EdDSA signatures.
- The EdDSA private key and Apple signing credentials must never be committed to the repository.
- AirCiller may check while idle. It must not check, download or install during media analysis, preparation or playback.
- Installation always requires a visible user action.

See Sparkle's [security and publishing documentation](https://sparkle-project.org/documentation/publishing/) for the release format and signing process.

## Downloaded components

AirCiller needs two managed components:

| Component | Purpose | Planned location |
| --- | --- | --- |
| FFmpeg and ffprobe | Media inspection and packaging | `~/Library/Application Support/AirCiller/Components/FFmpeg/<version>` |
| Python and pyatv | AirPlay 2 discovery and control | `~/Library/Application Support/AirCiller/Components/AirPlay/<version>` |

Component archives will be hosted as GitHub Release assets. A signed manifest will record the version, architecture, minimum macOS version, size, SHA-256 digest, source URL and license information.

Downloads must use a staging directory. AirCiller verifies the archive before moving it into the component directory. A failed or cancelled download leaves the current component untouched. The app keeps one previous working version for rollback.

If AirCiller distributes an FFmpeg binary, the matching source archive, build configuration and license notice must be available beside it. See [FFmpeg's legal guidance](https://ffmpeg.org/legal.html).

## Local audit

Run the distribution check against a built app:

```sh
./Scripts/audit_distribution.sh /path/to/AirCiller.app
```

The current local build is expected to fail this check until Developer ID signing and notarization are configured.

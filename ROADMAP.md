# Technical roadmap

Current work focuses on reliability and measurable playback behavior.

## Next isolated fixes

1. [x] Unify FFmpeg/ffprobe execution behind a cancellable process so Stop or switching files immediately ends abandoned analysis, preparation, and OCR work.
2. Add a synthetic attached-artwork fixture and always select/map the exact index of the real video stream.
3. [x] Select the local address from the effective route to the Apple TV on Macs with multiple interfaces or a VPN, while keeping the current behavior as a fallback.
4. Add characterization tests for the AirPlay controller, Keychain races, and corrupt persistence before splitting the large coordinator files.

Each playback change must be validated locally first, then independently through direct MP4 and HLS/fMP4, and finally on a physical Apple TV before installation.

## Maintenance and publication

- [x] Use English as the development language with a complete native Spanish localization that follows the macOS language setting.
- [x] Publish the main documentation and GitHub templates in English and state that the app includes English and Spanish localization.
- [ ] Add a reproducible process for regenerating and verifying `requirements.lock`; major upgrades such as protobuf 7 require an updated lock, full local checks, and physical validation when they can affect the AirPlay engine.
- [x] Enable GitHub private vulnerability reporting.
- [x] Create the first version tag and public release after the localized build passes the physical Apple TV matrix.
- [ ] Sign releases with Developer ID, enable Hardened Runtime and notarize them with Apple.
- [ ] Package a fixed Python runtime so the AirPlay engine does not depend on a path from the build Mac.
- [x] Show the active Python/AirPlay and FFmpeg versions, paths, sources, and explicit Homebrew maintenance actions.
- [ ] Replace the Homebrew-dependent setup with managed component downloads, signed manifests, progress, cancellation and rollback.
- [x] Integrate Sparkle 2 with a verified framework download, signed appcast support, manual checks, optional automatic checks and explicit installation.
- [x] Publish the first signed appcast through GitHub Releases after generating the EdDSA key and configuring the final HTTPS feed location.

## Settings

1. [x] Add native panes for Playback, Updates, Components and Storage.
2. [ ] Extend the existing preferred subtitle language with separate choices for standard, forced and SDH tracks.
3. [x] Add a preferred audio language with the file's default track as fallback. Audio conversion continues to require confirmation for each movie.
4. [x] Show component version, source, location and status, with explicit Homebrew actions, activity and cancellation.
5. Add actions to export a sanitized diagnosis and reset Apple TV authorization.
6. Consider an OpenSubtitles.com search for the selected movie. It must be initiated by the user, use the current REST API and store credentials in Keychain.

## Library

1. [x] Keep Playlist and Recents rows on a consistent two-line rhythm while exposing the complete filename on hover.
2. [ ] Add keyboard reordering and clearer VoiceOver position feedback to complement drag and drop.

## Now Playing and remote control

1. [x] Publish duration, elapsed time, playback state and non-live status to macOS Now Playing.
2. [x] Accept basic play, pause, seek and skip commands from macOS and the iPhone Apple TV Remote while synchronizing the main timeline.
3. [x] Trigger automatic Now Playing presentation on the iPhone Lock Screen without an AirCiller iOS or tvOS app.
4. [ ] Determine whether public macOS APIs can reliably add the original movie title and AirCiller artwork to the Apple TV-owned Lock Screen card.
5. [ ] Validate long pause, end-of-file, stop and rapid command edge cases across the Mac, physical Apple TV remote and iPhone.

## Functional candidates

1. [x] Reuse the Apple Vision pipeline for local, on-demand DVD VobSub OCR.
2. [x] Add a visible limit and controls for prepared-media and subtitle caches.

## Out of scope

- Telemetry or analytics.
- Cloud storage or uploading movies/subtitles.
- A permanent server or background indexing.
- Silent transcoding.
- Heavy dependencies without a demonstrated benefit.

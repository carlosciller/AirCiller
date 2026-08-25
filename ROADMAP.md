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
- [ ] Add a component manager for Python/pyatv and FFmpeg with signed manifests, progress, cancellation and rollback.
- [ ] Add a Sparkle 2 updater with a signed feed and explicit installation. Updates remain idle during analysis, preparation and playback.

## Settings

1. Add native panes for Playback, Updates, Components and Storage.
2. Move the preferred subtitle language into Playback settings and add separate choices for standard, forced and SDH tracks.
3. Add a preferred audio language with the file's default track as fallback. Audio conversion continues to require confirmation for each movie.
4. Show component version, source, location, size and status. Downloads include a progress bar and Cancel button.
5. Add actions to export a sanitized diagnosis and reset Apple TV authorization.
6. Consider an OpenSubtitles.com search for the selected movie. It must be initiated by the user, use the current REST API and store credentials in Keychain.

## Now Playing and remote control

1. [ ] Make Now Playing metadata complete and reliable on macOS: original movie title, artwork, duration, elapsed time, playback state and non-live status must stay accurate from start to finish.
2. [ ] Finish bidirectional remote synchronization. Play, pause, seek and skip commands from AirCiller, the physical Apple TV remote and the iPhone Apple TV Remote must update every other control surface immediately without losing the AirPlay 2 session.
3. [ ] Investigate automatic Now Playing presentation on the iPhone Lock Screen for an AirPlay 2 queue started by the Mac. Document the operating-system and entitlement boundary, and do not promise parity with native tvOS streaming apps unless it works without requiring an AirCiller app for tvOS or iOS.
4. [ ] Validate the complete flow on a physical Apple TV and iPhone: automatic Lock Screen appearance where supported, correct title/artwork/timing, no Live label, two-way play/pause/seek/skip, long pause and resume, end-of-file behavior, and clean removal after Stop.

## Functional candidates

1. [x] Reuse the Apple Vision pipeline for local, on-demand DVD VobSub OCR.
2. [x] Add a visible limit and controls for prepared-media and subtitle caches.

## Out of scope

- Telemetry or analytics.
- Cloud storage or uploading movies/subtitles.
- A permanent server or background indexing.
- Silent transcoding.
- Heavy dependencies without a demonstrated benefit.

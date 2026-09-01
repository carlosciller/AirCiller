# Technical roadmap

AirCiller advances through small, isolated changes. Playback work must preserve the direct MP4 HDR/Dolby Vision route and the HLS/fMP4 route independently, then be checked on a physical Apple TV before release.

## Next candidates

1. [x] Normalize receiver identity across IPv4, IPv6 and VPN interfaces, and distinguish confirmed media requests from filtered performance metrics.
2. [ ] Validate end-of-file and rapid play, pause, seek and stop sequences across the Mac, physical Apple TV remote and iPhone Remote.
3. [ ] Add keyboard reordering and clearer VoiceOver position feedback to Playlist.
4. [ ] Determine whether public macOS APIs can reliably add the original movie title and AirCiller artwork to the Apple TV-owned Lock Screen card.
5. [ ] Consider a user-initiated OpenSubtitles.com search for the selected movie. It must use the current REST API and keep credentials in Keychain.

## Reliability baseline

- [x] Cancel FFmpeg, analysis, preparation and OCR work immediately when playback stops or the selected file changes.
- [x] Prevent authorization loops with one bounded automatic renewal.
- [x] Prevent pairing retries from overlapping an older helper and force termination if it ignores a normal cancellation.
- [x] Serialize AirPlay credential access and recover safely from corrupt library persistence.
- [x] Require the bundled Python engine to import and execute `pyatv` and its runtime dependencies, not merely start Python.
- [x] Select the local address from the effective route to the Apple TV on Macs with multiple interfaces or a VPN.
- [x] Select the real video stream when a file contains attached artwork.
- [x] Validate long pause, resume, seeking, stop and receiver exit on a physical Apple TV.
- [x] Convert Blu-ray PGS and DVD VobSub subtitles locally and on demand with Apple Vision.
- [x] Bound prepared-media and subtitle caches and expose their controls in Settings.

## Build and distribution

- [x] Use English for development and public documentation, with complete native English and Spanish localization in the app.
- [x] Generate and verify `requirements.lock` with fixed Python, pip and pip-tools versions. Major changes such as protobuf 7 still require a reviewed lock, full local checks and physical Apple TV validation.
- [x] Include the validated FFmpeg and AirPlay engines in each app release, with compact version details under Diagnostics and no separate maintenance controls.
- [x] Integrate Sparkle 2 with signed update metadata and explicit installation.
- [x] Publish the source, signed appcast and release archives through GitHub.
- [ ] Sign releases with Developer ID, enable Hardened Runtime and notarize them with Apple. This remains blocked until an Apple Developer Program membership is available.

## Product foundations

- [x] Native Playback, Updates and Storage settings.
- [x] Separate preferred languages for standard, forced and SDH subtitles, plus preferred audio language.
- [x] Sanitized diagnostics export and an explicit Apple TV authorization reset.
- [x] Consistent Playlist and Recents rows with full filenames on hover.
- [x] macOS Now Playing integration with play, pause, seek and skip commands from the Mac and iPhone Remote.
- [x] Automatic Now Playing presentation on the iPhone Lock Screen.

## Out of scope

- Telemetry or analytics.
- Cloud storage or uploading movies or subtitles.
- A permanent server or background indexing.
- Silent transcoding.
- Heavy dependencies without a demonstrated benefit.

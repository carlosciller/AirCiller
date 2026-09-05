# Roadmap

AirCiller should remain quick to open, straightforward to control and dependable through a whole movie. This is the order of work, not a release schedule.

The 0.12.1 stability release covers playback controls, authorization, track editing and malformed data. OpenSubtitles, keyboard Playlist reordering, local PGS/VobSub OCR, language preferences and bundled engines are already available.

[The review record](Docs/STABILITY_REVIEW.md) records the local checks, CI and completed physical Apple TV tests. Release and signing steps are documented in [Distribution](DISTRIBUTION.md); user-facing changes are in the [release notes](CHANGELOG.md).

## Next: small compatibility additions

Each item needs a real sample, clear failure messages and a separate release decision.

1. External PGS and VobSub files through local OCR, including paired files, timing and palettes.
2. TS, MTS and M2TS containers carrying already-compatible H.264 or HEVC.
3. Original FLAC audio through HLS/fMP4, subject to successful stereo and multichannel Apple TV tests.
4. Additional text subtitle formats. Check timing and styling individually; evaluate TTML/IMSC1 separately.

## Later

- An App Intent or Shortcut to send a file to Apple TV.
- Reliable title and artwork on the iPhone Lock Screen. Working remote control takes priority.
- DVB and XSUB subtitle OCR with suitable samples.
- Preserve library entries when an external drive is disconnected.

AV1 passthrough remains research only. A device decoder does not establish support in its AirPlay video receiver.

## Distribution

Playback engines stay pinned and bundled with the app. Dependency updates require a regenerated lock, import and packaging checks, and applicable hardware tests. Proposals that only change `requirements.in` are incomplete.

Developer ID and notarization are blocked until an Apple Developer Program membership is available. Sparkle signatures do not replace notarization.

## Boundaries

No analytics, cloud library, permanent server, background indexing or silent conversion. Do not upload movies or bitmap subtitles for recognition. Preserve original files and keep direct MP4 and HLS/fMP4 packaging changes in separate deliveries.

Completed work belongs in the [changelog](CHANGELOG.md); validation belongs in [TESTING.md](TESTING.md).

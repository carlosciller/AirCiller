# Roadmap

AirCiller should remain quick to open, straightforward to control and dependable through a whole movie. This is the order of work, not a release schedule.

The 0.12.1 stability release covers playback controls, authorization, track editing and malformed data. OpenSubtitles, keyboard Playlist reordering, local PGS/VobSub OCR, language preferences and bundled engines are already available.

[The review record](Docs/STABILITY_REVIEW.md) records the local checks, CI and completed physical Apple TV tests. Release and signing steps are documented in [Distribution](DISTRIBUTION.md); user-facing changes are in the [release notes](CHANGELOG.md).

## First: automated playback checks

Build a local, on-demand test runner for the actual AirCiller app and physical Apple TV. Keep it outside the everyday interface, with no extra Apple TV app or permanent service.

1. Prepare a small, repeatable set of short clips covering direct HDR/Dolby Vision and HLS/fMP4 with and without subtitles. Include audible content and visible cues from the start. Keep private media outside Git and preserve originals.
2. Exercise the Swift application, bundled AirPlay helper and local server together. Check receiver-reported progress, pause/resume, rapid seeks, track changes, cancellation, natural completion and a single transition to the next Playlist item. Testing only the helper would miss app lifecycle failures.
3. Use timeouts and one result report, with local checks, receiver evidence and human observations recorded separately. A successful command or an advancing Mac timer is not proof of television playback. Restore test settings and Playlist order, and leave no helper or playback server running. Do not interrupt an existing viewing session or reset pairing automatically.
4. Group any remaining visual, audio and physical-remote checks into one short session. Automated receiver status cannot certify sound, subtitle appearance or correct HDR output. Ask for individual follow-up only when a case fails or remains uncertain.
5. Run checks according to the change: documentation needs no television, interface changes need interface checks, shared controls need both affected playback paths, and engine or format changes need their audiovisual cases. Keep long-pause and large-file stress checks for changes that can affect them; short clips do not replace those tests.

Acceptance: one command runs the selected cases, reports failures with useful evidence and finishes with one consolidated manual checklist when needed. This runner is planned, not implemented; the current [validation rules](TESTING.md) still apply.

## Then: more formats without re-encoding

Prioritize keeping both video and audio in their original encoded formats. Remuxing into a compatible streaming container is allowed; it must not silently become audio or video transcoding.

1. TS, MTS and M2TS containers carrying already-compatible H.264 or HEVC and original audio accepted by the receiver.
2. Original FLAC audio through HLS/fMP4, subject to successful stereo and multichannel Apple TV tests. This remains an investigation, not a promise of receiver compatibility.

Each addition needs a representative sample, copy-only audio/video verification, the relevant automated and audiovisual checks, clear rejection messages and a separate release decision. Add support only after the AirPlay receiver accepts it; FFmpeg being able to read a format is not enough.

## After that: subtitle additions

- External PGS and VobSub files through local OCR, including paired files, timing and palettes.
- Additional text subtitle formats. Check timing and styling individually; evaluate TTML/IMSC1 separately.

OCR and conversion to selectable text are separate from original audio/video passthrough. Never burn subtitles into the picture, upload them for recognition or modify the source files.

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

# Roadmap

AirCiller should remain quick to open, straightforward to control and dependable through a whole movie. This is the order of work, not a release schedule.

The latest published release is [0.12.0](https://github.com/carlosciller/AirCiller/releases/tag/v0.12.0). OpenSubtitles, keyboard Playlist reordering, local PGS/VobSub OCR, language preferences and bundled engines are already available.

## In progress: stability review

- Cancel pending authorization when Stop is pressed and ignore replies from old sessions.
- Distinguish an unavailable Keychain from a missing Apple TV credential.
- Commit track edits only when Apply is pressed.
- Make Recents selection consistent with Playlist and simplify playback controls using system materials and colors.
- Limit online subtitle responses during download; handle invalid timing and result data safely.
- Remove the unused runtime installer while retaining reproducible engine build tools.
- Integrate the measured ASS conversion and process-buffer improvements and their regression tests.

[The review record](Docs/STABILITY_REVIEW.md) tracks evidence and remaining checks. This candidate is not yet a published or physically validated release.

### Before release

1. Pass strict local checks and GitHub CI on the final candidate.
2. Check selection, keyboard navigation, track Apply/Cancel and layout in the built app.
3. Test direct HDR/Dolby Vision with audio and selectable subtitles, then HLS/fMP4 with and without WebVTT on Apple TV.
4. Check Stop during authorization and preparation, long pause/resume, natural completion and rapid remote commands.
5. Verify the signed update. Keep the working installed app and a rollback until the candidate is accepted.

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

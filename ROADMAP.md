# Roadmap

AirCiller should stay quick to open and dependable through a whole movie. This is
the order of work, not a release schedule. Completed changes are in the
[release notes](CHANGELOG.md); detailed evidence belongs in [Testing](TESTING.md).

## 0.15.0: library and seasons

0.15.0 adds season folders, natural episode order, watched status, saved progress
and native reordering. Movies enter Playlist before analysis; adding files keeps
an active session running. Imports are cancellable and report rejected inputs.

The [library record](Docs/LIBRARY_SEASONS.md) identifies tested behavior and limits.
Both video packagers and bundled engines are unchanged. Release and update steps
follow [Distribution](DISTRIBUTION.md).

## Next repairs

1. **SDR HLS audio timing.** Manual audio offsets can be discarded during
   preparation. Establish a shared presentation clock without skipping the
   opening video. Test positive and negative offsets, seeks, final audio and
   subtitle timing with the pinned engine, then verify Apple TV output.
   [Investigation](Docs/HLS_AUDIO_TIMING.md).
2. **Subtitles after seeking.** Investigate the brief HLS visibility gap using
   known cues, separating individual seeks, rapid commands and receiver controls.
   Repeat earlier segment experiments only with a new cause to test.
   [Playback checks](Docs/PLAYBACK_CHECKS.md).
3. **Focus and editing.** Check independent text-field Undo, focus after applying
   tracks, operation-specific Undo wording and long inspector content at minimum
   window size. [Interface record](Docs/NATIVE_UI_INTEGRATION.md).

## Faster playback startup

The maintainer readiness checkpoint for the dedicated startup work is complete.
The first delivery shipped in 0.13.0: bounded prepared-HLS caching, parallel text
extraction and process-lifecycle improvements. Its measurements and separate
audio-timing limitation are in [Startup optimization](Docs/STARTUP_OPTIMIZATION.md).
Do not restart that checkpoint or silently switch the maintainer's chosen model.

A further phase needs complete Play-to-picture-and-sound timings on Apple TV.
Tell the maintainer before starting so they can select the requested model and
effort. Keep implementation/preparation and final tests/publication separate.

- Measure analysis, subtitles, preparation, authorization, connection and first
  output separately. Include cold/warm caches and bitrate peaks.
- Compare bounded parallel work, reuse and engine behavior against a pinned
  baseline. Record regressions; newer dependencies are not proof of faster playback.
- Larger packaging changes need a separate design review. Preserve complete VOD,
  full duration, seeking, original media, HDR/Dolby Vision and selectable subtitles.
  Change one packager per delivery.

## Compatibility research

- **PCM/LPCM:** the 0.16.0 HLS candidate offers explicit lossless FLAC
  conversion for known integer precision and native layouts. Local media, UI,
  receiver controls and selected digital-output checks passed. SDR preserves
  the source clock with separate audio; HDR without subtitles stays multiplexed.
  Publication/installation are a separate phase. Direct HDR/subtitle MP4 remains
  outside this first expansion.
  [Investigation and matrix](Docs/AUDIO_EXPANSION.md).

- **FLAC layouts:** retain channel-mask overrides that fMP4 currently changes.
  Require representative samples and receiver output before widening passthrough.
  Do not relabel speakers. [Current support](Docs/FLAC_AUDIO.md).
- **Subtitles:** assess additional text formats individually, including TTML/IMSC1;
  investigate DVB and XSUB OCR with suitable samples. Keep OCR local and selectable.
- **AV1 passthrough:** research only. A device decoder does not establish support
  in its AirPlay receiver. There is no promised video transcoder.

TS/MTS/M2TS, supported FLAC soundtracks, PGS and VobSub are already available.
Their limits are in [Compatibility](COMPATIBILITY.md), with separate
[transport-stream](Docs/TRANSPORT_STREAMS.md), [PGS](Docs/EXTERNAL_PGS.md) and
[VobSub](Docs/EXTERNAL_VOBSUB.md) records.

## Deferred and blocked

- **Apple Shortcuts:** implementation is preserved, but public ad hoc registration
  failed on the tested Mac. Resume with the signing/distribution decision and the
  remaining handoff checks. Finder Quick Actions and Services are outside that
  scope. [Shortcuts record](Docs/SHORTCUTS.md).
- **iPhone Lock Screen metadata:** remote control works; title and artwork on the
  Apple TV-owned card are not reliable.
- **Developer ID and notarization:** blocked until Apple Developer Program
  membership is available. Sparkle signatures do not replace notarization.

## Maintenance and distribution

Engines remain pinned and bundled. Dependency changes need a regenerated lock,
runtime imports, packaging checks and applicable playback validation. Current
protobuf and urllib3 proposals change only requirements.in; their CI failures are
lock mismatches, not evidence that the shipped runtime is broken. They are not
included in this release.

Keep the 165 MB logical bundle budget. Runtime trimming needs measured savings
and complete checks. The [on-demand playback runner](Docs/PLAYBACK_CHECKS.md)
provides sampled digital output, control and cleanup evidence without a permanent
service. Use only the authorized Apple TV screen/audio source.

## Boundaries

No analytics, cloud library, permanent server, background indexing or silent
conversion. Preserve originals. Keep credentials and private media out of Git.
Publication, update and rollback follow [Distribution](DISTRIBUTION.md).

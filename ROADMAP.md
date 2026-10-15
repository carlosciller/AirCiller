# Roadmap

AirCiller should stay quick to open and dependable through a whole movie. This is
the order of work, not a release schedule. Completed changes are in the
[release notes](CHANGELOG.md); detailed evidence belongs in [Testing](TESTING.md).

## 0.17.0 scope

Implemented and validated within the linked records' observation limits:

- **SDR manual audio synchronization.** Local conservation/cache matrices and
  receiver-control checks pass, including corrected Stop handling, saved source
  position, replay and track changes. Captured output covers +5/-5 seconds and
  switching between them; offline reassessments and fresh runs are identified
  separately. [Timing investigation](Docs/HLS_AUDIO_TIMING.md).
- **Explicit TrueHD-to-FLAC preparation.** HLS only, with manual audio timing at
  zero, declared 24-bit precision, matching mono/stereo/5.1(side)/7.1 labels and
  native 44.1/48/88.2/96/176.4/192 kHz rates. Local sample, internal-clock, HLS,
  cache and damaged-input checks pass. Sampled receiver output covers stereo and
  5.1(side) SDR and stereo HDR-source playback; native conversion-choice and
  inspector checks are recorded. Atmos objects are not retained. Physical
  speaker routing and playback-length 7.1 receiver output are not established.
  [Audio validation](Docs/AUDIO_EXPANSION.md).

DTS-HD MA lossless preparation is excluded from this delivery; its blocker is
recorded below. Release, CI, signed-download and native-update evidence is
separate from playback acceptance and follows [Distribution](DISTRIBUTION.md).

## Released scope

0.16.0 adds explicitly selected PCM/LPCM-to-FLAC lossless preparation on HLS
for the validated precision/layout cases, and opens Audio & Subtitles by default.
Publication, signed downloads, CI and the native Sparkle update were verified.
The [audio record](Docs/AUDIO_EXPANSION.md) retains the bounded playback evidence.

0.15.0 adds season folders, natural episode order, watched status, saved progress
and native reordering. Movies enter Playlist before analysis; adding files keeps
an active session running. Imports are cancellable and report rejected inputs.

The [library record](Docs/LIBRARY_SEASONS.md) identifies tested behavior and limits.
Release and update steps follow [Distribution](DISTRIBUTION.md).

## Next repairs

1. **Subtitles after seeking.** Investigate the brief HLS visibility gap using
   known cues, separating individual seeks, rapid commands and receiver controls.
   Repeat earlier segment experiments only with a new cause to test.
   [Playback checks](Docs/PLAYBACK_CHECKS.md).
2. **Focus and editing.** Check independent text-field Undo, focus after applying
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

- **Lossless audio coverage:** widen PCM/LPCM precision, rates or layouts only
  with their own preservation and receiver checks. TrueHD needs a valid,
  playback-length 7.1 source for receiver coverage; 16-bit TrueHD remains
  unverified. Do not loop encoded TrueHD fragments to manufacture that evidence.
  Direct HDR/subtitle MP4 and nonzero manual audio timing remain outside the
  lossless-conversion route.
  [Investigation and matrix](Docs/AUDIO_EXPANSION.md).

- **FLAC layouts:** retain channel-mask overrides that fMP4 currently changes.
  Require representative samples and receiver output before widening passthrough.
  Do not relabel speakers. [Current support](Docs/FLAC_AUDIO.md).
- **Subtitles:** assess additional text formats individually, including TTML/IMSC1;
  investigate DVB and XSUB OCR with suitable samples. Keep OCR local and selectable.
- **AV1/VP9:** parked for the maintainer's third-generation Apple TV 4K workflow.
  Revisit only for a concrete collection/device need and actual AirPlay evidence.
  There is no promised video transcoder; MPEG-2 and DCP remain outside this work.

TS/MTS/M2TS, supported FLAC soundtracks, PGS and VobSub are already available.
Their limits are in [Compatibility](COMPATIBILITY.md), with separate
[transport-stream](Docs/TRANSPORT_STREAMS.md), [PGS](Docs/EXTERNAL_PGS.md) and
[VobSub](Docs/EXTERNAL_VOBSUB.md) records.

## Deferred and blocked

- **DTS-HD MA lossless preparation:** damaged lossless extensions can return
  success under strict decoder flags while changing samples. Diagnostic guards
  do not cover every observed failure. Resume only with a decoder guarantee or
  full bitstream qualification, representative extension-bearing inputs and an
  independent lossless reference. A DTS-core fallback is not acceptable, and
  DTS:X object preservation is not promised. [Investigation](Docs/AUDIO_EXPANSION.md).
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

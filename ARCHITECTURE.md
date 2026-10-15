# Architecture

AirCiller consists of a native macOS application, bundled media tools and an
on-demand Python helper for AirPlay 2. No playback server or helper stays running
independently of the app's active work.

Local certificate-signed builds also embed an on-demand, read-only
[credential service](Docs/CREDENTIAL_SERVICE.md). It authenticates XPC callers
and keeps its executable unchanged across app rebuilds. It shares the existing
AirPlay Keychain store and has no network listener or permanent background
registration. Public ad hoc builds retain the original direct Keychain implementation.

## Main flow

Movie admission stores compatible inputs in Playlist before analysis. Folder
imports use a cancellable, on-demand scanner and persist season membership,
order, expansion, watched status and progress. Adding inputs preserves an active
analysis, preparation or playback session. See
[library behavior](Docs/LIBRARY_SEASONS.md).

1. `MediaProbeService` uses `ffprobe` to inspect the container, video, audio,
   subtitles and chapters.
2. `StreamCoordinator` selects a preparation path and enforces the chosen audio
   policy without modifying the original file. Required audio conversion is an
   explicit user choice.
3. `LocalHTTPServer` exposes the complete prepared result temporarily on the
   local network, using HTTP ranges and a random session path.
4. `AirPlayController` starts `airplay_helper.py`, which authenticates with the
   Apple TV and controls the AirPlay 2 queue through pyatv.
5. Receiver events update playback state, position, completion and the Mac's
   Now Playing information. Receiver status is distinct from observed output;
   it does not guarantee title/artwork on the iPhone's Apple TV-owned card.

## Media paths

| Path | Use | Invariant |
| --- | --- | --- |
| Direct MP4 | HDR/Dolby Vision with selected subtitles | Encoded video is copied; subtitles remain selectable |
| HLS/fMP4 VOD | SDR, with or without WebVTT; HDR without selected subtitles | Every playlist is finalized before playback starts; encoded video is copied |

SDR HLS has separate video and audio renditions. HDR HLS remains multiplexed.
The paths share discovery, controls and the HTTP server, but retain independent
packagers and path-specific validation. A single delivery must not change both
packagers; shared control/server changes require assessing effects on both.

`HLSPreparationService` owns HLS preparation. It joins concurrent base packaging
and text extraction before segmenting subtitles against the finalized timeline.
Bitmap OCR runs after packaging. `StreamCoordinator` owns cancellation, temporary
serving, receiver startup and the local per-attempt timing trace.

## Audio and presentation clocks

Keep Original is the default. Compatible audio is copied; an unsupported track
requires a choice before audio conversion. E-AC-3 and stereo AAC outputs are
lossy. The explicit lossless FLAC option accepts eligible PCM/LPCM and TrueHD
tracks on HLS with manual audio adjustment at zero. It preserves channel-based
samples, not Atmos objects. DTS-HD MA lossless preparation is not enabled.
Exact precision, rate and layout limits belong in
[Compatibility](COMPATIBILITY.md), with evidence in the
[audio record](Docs/AUDIO_EXPANSION.md).

TrueHD-to-FLAC preparation uses standard FLAC block sizes and strict decoder
diagnostic handling. It rejects decoder warnings/errors outside the precisely
qualified muxer exception; process exit success alone does not establish clean
decoding. Cached TrueHD output uses its own preparation-policy version.

Adjusted SDR HLS uses a shared presentation clock and complete leading/trailing
intervals. Delaying audio retains the opening video and its delayed audio tail.
Advancing audio holds the first encoded video frame while retaining the leading
audio. Video is not encoded or discarded. `HLSAudioTimeline` finalizes rendition
intervals, GAP entries and `HLSAudioTimelineInfo` before cache admission and
subtitle segmentation. Ordinary zero-adjustment HLS and the direct MP4 clock
policy remain separate. See the [timing record](Docs/HLS_AUDIO_TIMING.md).

`MoviePlaybackTimeline` maps between two clocks:

- The original movie clock is used for saved progress, history and chapter positions.
- The prepared presentation clock is used for the receiver, active duration and slider.

`StreamCoordinator` translates resume/chapter requests into presentation time
and restores source time during cleanup. A local Stop acknowledgement must not
republish the retired presentation position. A receiver-initiated Stop publishes
its final position before cleanup. Subtitle adjustment remains independent and
is mapped onto the finalized video timeline.

## Preparation cache and ownership

`PreparedMediaCache` retains immutable base video/audio and the adjusted timeline
metadata needed to interpret them. Each session receives independent playlist
and timeline-metadata copies; shared media fragments stay immutable. Selected
subtitles are finalized for the session, not stored as part of the base package.

Cache identity includes the source, selected audio/output, adjustment and pinned
engine/preparation policy. Invalid or obsolete packages are not reused. The
preparation task cancels and joins its child work before its caller can remove
the session directory or start a replacement. Storage controls remain local.
See the [startup record](Docs/STARTUP_OPTIMIZATION.md) for the original cache
design and the audio/timing records for subsequent policy changes.

## Boundaries

- Swift/AppKit/SwiftUI: interface, state, preparation coordination and local server.
- FFmpeg/ffprobe: inspection, remuxing and explicitly selected audio conversion.
  A pinned build is bundled with each release; video is not transcoded.
- CPython and locked Python packages: the AirPlay 2 bridge. The build fetches
  verified runtime archives and bundles the tested result.
- Apple Vision: local, on-demand OCR for PGS and VobSub; no remote OCR service.
- Sparkle and optional OpenSubtitles requests: application updates and explicitly
  requested subtitle searches/downloads, not a cloud library or telemetry service.

## State and data

Playlist, season metadata, watched state, saved positions and history are stored
in `UserDefaults`. AirPlay and OpenSubtitles credentials have their established
Keychain stores. Legacy movie entries remain readable without optional season
fields. Prepared-media, downloaded-subtitle and OCR caches remain on the Mac.
Original media is not modified. See [Privacy](PRIVACY.md) for data and network
boundaries and [Distribution](DISTRIBUTION.md) for packaging and update ownership.

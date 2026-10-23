# Playback core review, October 2026

Reviewed on 23 October against `68410591e3786705f54938326e152be94fa564d1`
and the working changes retained by the main review. This is the playback
sub-review of [the candidate review](REVIEW_2026_10.md), not release acceptance.
It records code inspection and local regressions. No receiver, capture source,
installed app, credentials or system settings were used or changed for this
sub-review.

## Corrections selected

### Direct startup can outlive its session

`StreamCoordinator.beginDirectHDRSubtitleStreaming` awaited the prepared-file
probe, AVAsset properties, subtitle selection and a player seek without
consistently checking whether Stop or a replacement movie had retired the
session. A cancelled continuation could therefore reach shared player,
observation and status mutations belonging to a newer session. The HLS startup
already contained comparable ownership guards.

The direct path now checks both task cancellation and session identity after
those suspensions and after the AirPlay/HTTP startup waits. Neither packager nor
its media arguments changed.

`DirectStartupCancellationCheck` exercises the actual ownership checkpoint
through controlled suspensions: current session, Stop, replacement session and
task cancellation while the session ID still matches. It also checks that the
replacement remains active and retains its power assertion. This is a
deterministic checkpoint regression, not a simulation of AVFoundation or a claim
that a television displayed the candidate.

### A local clock was being reported as fresh receiver evidence

`AirPlayController` publishes an interpolated UI position every 500 ms.
`StreamCoordinator` previously assigned a new receiver-observation timestamp on
every one of these callbacks. An unchanged or unavailable receiver observation
could consequently appear recent to private-control clients.

The controller now publishes a separate `AirPlayReceiverObservation` only when
handling a receiver event. Command acknowledgements and the UI timer do not
renew it. Position and duration are optional: an event without raw timing does
not borrow an interpolated value and present it as a receiver measurement.
The coordinator consumes this separate callback; the main review owns the
private gateway's interpretation of it.

The controller regression passed with Swift 6 strict concurrency and warnings
as errors. It covers a synthetic event through the helper decoder, a subsequent UI tick,
command-source pause/resume/seek acknowledgements, an untimed receiver event,
a later timed receiver status and stopped/retired sessions. It does not contact
an Apple TV.

### Cancelling authorization could retain transition power

Autoplay holds a transition power assertion while waiting for authorization.
The pairing dialog's cancellation previously stopped controller work without
notifying the coordinator that owned that assertion.

The controller now notifies cancellation. The coordinator records which remote
session requested renewal and releases only that session's idle transition
assertion. It does not terminate a replacement session, active analysis or a
conversion decision. The coordinator regression covers ordinary cancellation,
teardown preserving a replacement transition, and a late cancellation after a
replacement has started. No real Keychain item is involved.

### Diagnostic demand omitted audio segments

For ordinary HLS with separate audio, `packagedHLSProfile` combined audio and
video by array index. Keyframe-based video segments and audio segments can have
different boundaries and counts. Some audio segments were omitted from totals,
and unrelated intervals were paired when estimating a peak.

The regression uses two 10-second video segments and four 5-second audio
segments. Before correction it reported 8.8 kbit/s for both average and peak.
The fixture contains 33,000 bytes over 20 seconds, so its average is
13.2 kbit/s. The corrected time-based combination reports that average and a
21.6 kbit/s peak over its six-second window. The strict local diagnostics suite
passed after the correction. These are fixture results, not network throughput
measurements.

Only diagnostics changed. The segment sizes and durations describe a
piecewise-average demand model; they do not reveal packet-level instantaneous
bitrate or receiver buffering.

### Direct HDR extraction mistook interleaved bytes for video

The main candidate check exposed a direct-MP4 failure before AirPlay started.
The isolated prepared fixture `direct-hdr-diagnostic.mp4` contains valid HDR
mastering-display and content-light metadata. It is not missing HDR metadata.
Its first media payload is E-AC-3 at byte 16,777,264, followed by text at
16,781,104; its first HEVC sample begins at 16,781,140. The control extracted
from the beginning of the source has HEVC at the first payload byte instead.

The direct injector previously scanned the whole initial interleaved `mdat`
region as length-prefixed HEVC, falling back to every byte offset if the first
sequence found no static SEI. Audio/text bytes could therefore produce
SEI-shaped candidates with false, very large lengths. The real fixture failed
with `unsupportedConfiguration`; the retained process sample shows execution
in that fallback and the shared SEI decoder. A synthetic audio-shaped payload
with an oversized false SEI reproduces the same old failure.

The direct path now derives exact sample ranges from `stco` or `co64`, `stsc`
and `stsz` in the same `stbl` as its selected `hvcC`, including the sample
description index. It parses NAL lengths only inside those HEVC sample ranges.
There is no arbitrary-byte fallback in this path. Sample-table counts, runs,
offsets and sizes are checked before mutation. The format handling follows
Apple's [sample-to-chunk table](https://developer.apple.com/documentation/quicktime-file-format/sample-to-chunk_atom/sample-to-chunk_table),
[sample-size](https://developer.apple.com/documentation/quicktime-file-format/sample_size_atom)
and [chunk-offset](https://developer.apple.com/documentation/quicktime-file-format/chunk_offset_atom)
documentation.

This is a bounded first-sample search for FFmpeg's prepared regular MP4: at
most the first 256 track samples within the existing 32 MiB prefix. It retains
distinct static metadata NALs across those samples. It does not search the
whole movie or silently continue without required metadata. Unsupported or
invalid tables fail before modifying the file. HLS extraction and the shared
SEI-message decoder were not changed.

`DirectHDRSampleTableSmokeTest` passed with Swift 6 strict concurrency and
warnings as errors, including an unoptimized build. It covers 32/64-bit chunk
offsets, constant/variable sample sizes, changing samples per chunk, a second
sample description, separate mastering/light NALs, idempotence, absent real
metadata and six malformed-table/sample cases. Failures leave the input bytes
unchanged. Success checks the metadata inside `hvcC`, identical media bytes,
unchanged file length and exact sample-table preservation.

Both actual prepared fixtures passed the new local verifier. The failing
fixture remains 157,164,645 bytes and has unchanged `mdat`/suffix SHA-256
`c47887b4af2fbff435b8fc3b29d5dfaf4dd2b2e5a68edda529cfa85aa6f044b8`.
The source-start control's unchanged payload hash is
`a8ca7305e617f9fba3fa640406673377d7699af0f73e2bcea8d8bc70e11c4099`.
All tracks' `stco`/`co64`, `stsc` and `stsz` bytes, media positions and file
lengths are identical before and after injection. Verification operates on
new disposable copies; neither original fixture was patched to make it pass.

One optimized process run per implementation used the same failing fixture
and `DirectHDRConfigurationSmokeTest`, including its copy/startup overhead:

| Implementation | Outcome | Wall time | Maximum resident bytes |
| --- | --- | ---: | ---: |
| Prior whole-payload search | `unsupportedConfiguration` | 10.22 s | 2,664,103,936 |
| Track-bounded search | Metadata injected | 0.24 s | 73,302,016 |

These are failure-versus-success measurements, not a claim of equivalent-work
speedup. The old negative output and process sample remain retained. The new
test is included in the local gate; physical direct-route acceptance belongs
to the main candidate ledger, not this local verifier.

For scope verification, the source block from HLS `injectStaticMetadata` through
the shared NAL search has SHA-256
`3598a702bc11ace8e0fdd9306f08963be4ea4f4c1e3f49fd83a61385161a935c`
both before and after this correction. The SEI decoder and subsequent helpers
share hash `89449fc9582fd51f6fb99f2c84d623497faaa2ee28ddf32b3904975b207c4735`.
`HLSPreparationService.swift` and `VODCommandBuilder.swift` also remain
byte-identical to their pre-fix versions. This supports retaining the main
review's HLS evidence without repeating an unrelated format matrix.

## Remaining evidence boundary: first HTTP request

`LocalHTTPServer.beginTransfer` sets `hasConfirmedMediaRequest` for any client,
even when that client is excluded from receiver telemetry. The local AVPlayer
can request prepared resources. `waitForReceiverMediaRequest` consumes this
generic flag while its status text describes a receiver request. The existing
`HTTPServerSmokeTest` explicitly checks that an excluded client still sets it.

This is a confirmed attribution limitation, not evidence of a new playback
failure: AirPlay startup also awaits its separate playing event. HTTP behavior
was deliberately left unchanged in this review.

Before using this flag to subdivide receiver startup latency, separate generic
resource access from requests attributable to the selected receiver. A focused
regression should distinguish local preview reads, receiver playlist/init
reads, and receiver media reads. The measurement must also name whether its
endpoint is request arrival, first body byte or completed transfer. None of
these alone proves visible image or audible sound. Existing timings must not be
retroactively relabelled as receiver-only measurements.

## Performance candidates, not measured savings

1. **Prepared-cache metadata reads.** `validatedFiles` hashes playlist metadata
   in `matches`, then reads it again through `baseNames`/`playlistNames` to
   validate references. Checkout copies and verifies that metadata again.
   Admission has additional source, staged-copy and staged-validation passes.
   A bounded metadata read could supply both digest and parsing within one
   validation pass. Retain verification of the copied artifact and source
   identity before publication. Media payloads are already hard-linked and
   checked with file attributes, not repeatedly hashed. A benchmark should
   count opens, bytes and wall time for equal segment counts; no speedup is
   claimed here and no cache code changed.
2. **Overlapping full-source demand analysis.** HLS startup cancels an ongoing
   demand scan; the direct path does not have the same explicit cancellation.
   A full packet analysis may compete with direct preparation for source I/O.
   Measure the overlap with the same media and cache state before changing
   scheduling. No timing benefit was established in this sub-review.

No change to AirPlay session setup, segment duration, encoding, receiver
buffering or HTTP transfer strategy is justified by these observations alone.

## Benchmark reference repair

The first local benchmark attempt, retained in
`.build/startup-benchmark/run.zo0TFk`, stopped at strict served-output parity.
Comparing both generated directories showed differences only in the three
WebVTT segment files. Video, audio, initialization segments and all playlists
were identical. For example, the first caption from 1.250 to 7.750 seconds was
split into contiguous one-second cues by commit `1765a82` (PR #34, HLS subtitle
restoration after seeking). That committed correction postdates the historical
`558b235` benchmark reference; it is not a new difference from this candidate.

The benchmark now accepts an explicit third argument, `historical` or `head`.
The default retains the original frozen sequential baseline. `head` freezes
the current committed SHA and runs that revision's actual
`HLSPreparationService`, with no app cache, against the working candidate.
Both modes still require identical fixture hashes, durations, complete served
inventories and byte-for-byte comparisons. The reference kind, commit and
source hashes are retained. The historical mismatch is not suppressed, and
its unequal outputs are not used to claim a performance gain.

`Scripts/benchmark_startup.sh 3 small head` completed successfully, with output
retained in `.build/startup-benchmark/run.VnfdJs`. The summary records reference
`68410591e3786705f54938326e152be94fa564d1`. All 24 samples passed complete
inventory, duration and byte-for-byte parity: 16 served files per sample.
The fixture was 13,865,608 bytes; its prepared duration was 18.026167 seconds.

| Preparation mode | SubRip median | ASS median |
| --- | ---: | ---: |
| Committed reference, no app cache | 28.709 ms | 24.731 ms |
| Candidate, no app cache | 26.385 ms | 28.076 ms |
| Candidate, initially empty app cache | 29.460 ms | 29.555 ms |
| Candidate, previously filled app cache | 14.885 ms | 14.749 ms |

There are only three observations per cell. Reference and candidate no-cache
ranges overlap; the median difference changes direction between subtitle types.
This does not establish a speed improvement or regression. The warm-cache
effect uses the existing cache, not a new optimization from this review.
Fixture generation, probing, unmeasured cache fill and parity checks are outside
the interval. It measures local preparation, not Play-to-image/sound, HDR, OCR,
large-file behavior or a cold operating-system cache. The independent resource
monitor self-test passed; very short child-process RSS peaks can still be missed.
The historical negative run remains retained separately.

## Inspection coverage and limits

The review followed control and failure paths in these areas:

- `StreamCoordinator`: load/start/stop, direct and HLS preparation, ownership,
  authorization renewal, conversion consent, transition/playback power and
  progress callbacks. Library admission and native interaction are covered by
  the separate UI review.
- `AirPlayController`, `airplay_helper.py`, credential store/service client,
  pairing lifecycle/intent/retry, seek coalescing/reconciliation and helper
  command writes. Reviewed the playback-check process-local Keychain UI guard;
  did not read actual credentials or test signing/ACL changes.
- `MediaProbeService`, media models, analysis task ownership,
  `CancellableProcess`, `CapturedProcess`, VOD command/build lifecycle and HLS
  preparation. No FFmpeg or pyatv dependency upgrade was performed.
- Direct HDR metadata injection, HLS audio timeline metadata and adjustment,
  source/presentation time mapping, prepared-media cache admission/checkout and
  storage ownership.
- Local HTTP parsing, range serving, connection/transfer lifetime, routing and
  telemetry; stream-demand analysis and its diagnostics tests.
- Text/ASS, PGS and external VobSub preparation, Vision OCR, subtitle caching,
  WebVTT segmentation and VOD validation.

Inspection is not exhaustive state-space coverage. The existing test suite was
read where it supported a finding; it was not rerun wholesale by this agent.
Malformed-input hardening and legacy process-pipe readers are potential future
review areas, not newly reproduced product failures. The main candidate ledger
records the integrated strict gate, coordinator regression and any required
physical playback acceptance separately.

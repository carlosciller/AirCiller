# Preparation efficiency review

## Scope and validation selection

Follow-up to the bitmap terminal-cue/cache correction, still uninstalled and
awaiting receiver acceptance. Work is limited to bitmap preparation, reuse of
validated direct MP4 output and the cost of Matroska attachments. The Apple TV
is unavailable; do not start capture or playback. No engine update, HLS packager
change, publication or installation is included.

Measure an alternative before adopting it. Keep pixel/sample preservation and
cache correctness separate from timing. Use synthetic inputs, isolated bounded
caches and storage-guarded measurements. Test source/subtitle/settings changes,
cancellation, corrupt cache entries, budget/Off/clear and active-session survival.
The existing HLS cache must retain its behavior if shared storage is extended.
Run the complete strict local gate on the final candidate once. Changed playback
behavior still needs scoped receiver/output acceptance before release.

## Changes and measured scope

### Bitmap subtitle images

PNG compression stays lossless at level 6. The predictor changes from Paeth to
none. Three alternating pairs, each rendering 30 transparent subtitle images,
gave these medians:

| Variant | Seconds | Total PNG bytes |
| --- | ---: | ---: |
| Level 6, Paeth | 0.7435 | 5,618,160 |
| Level 6, none | 0.6246 | 4,506,090 |

This fixture took 16% less time and 20% less temporary space. All decoded frames
matched, including the frame count and timestamps. The SHA-256 of the decoded
`framemd5` output was
`cb60790a0f84a575080c4436a6334ecc463e6fd1e24025e4b192501c1d16dc5c`.
Lower compression levels were faster but more than doubled PNG storage, so they
were not selected. OCR recognition, concurrency and cue timing are unchanged by
this optimization. This measures PNG preparation, not complete OCR, real PGS
extraction or time to television picture.

Reproduce with `python3 -B Scripts/benchmark_bitmap_preparation.py` followed by
the absolute path to an explicit development FFmpeg. The development encoder
only generates fixtures; all timed processing uses the pinned bundled engine.
Final evidence: `.build/performance/run.1o5rsq2b/measurement.json`.

### Prepared direct MP4 reuse

Direct output now uses the existing prepared-media cache and its shared budget,
Off setting and Clear action. No additional cache limit or permanent service is
introduced. The key includes source and engine identities, exact mux settings,
external subtitle dependencies (including a VobSub companion), and recognized
subtitle text. A hit skips remuxing and HDR header injection. Metadata and local
player checks still run. Admission of a new result occurs only after those
checks. Cached media is immutable; eviction preserves active session links.

A rejected metadata validation invalidates a hit and rebuilds once. Cancellation
does not start a replacement preparation or evict an otherwise valid hit. HLS
cache identity and its separate subtitle handling are unchanged.

Three repetitions per mode on a synthetic 20-second H.264/AAC clip with an SRT
track produced these median preparation times:

| Mode | Seconds |
| --- | ---: |
| Cache disabled | 0.02691 |
| Empty cache, including admission | 0.02797 |
| Warm cache, including metadata validation | 0.00732 |

Every output had SHA-256
`dc0bfa0888e7319ac36253901509b1022c0f9cd6f5159d90eb5b1545dd31a456`.
The source hash also remained unchanged. These small local measurements prove
reuse without changed bytes; they do not predict savings for a full film. The
fixture exercises the direct command and cache service, not normal HDR routing,
HTTP/AVPlayer startup or the Apple TV.

Reproduce with `python3 -B Scripts/benchmark_direct_cache.py` followed by the
absolute path to an explicit development FFmpeg. Final evidence:
`.build/performance/run.0f4_i7dd/measurement.json`.

### Matroska attachment output

The old metadata query requested `extradata` and `-show_data` for every stream.
This hex-dumped font attachments even though the app only consumes codec
extradata for the selected HEVC video. The primary query now collects metadata
without those fields. HEVC identification uses a second query restricted to the
selected video stream. Track discovery, chapter data, HDR/DV side data and fonts
remain intact. No custom FFmpeg build or attachment removal is involved.

Three alternating pairs on a synthetic HEVC MKV with a 24 MiB attachment gave:

| Query | Median seconds | JSON output bytes |
| --- | ---: | ---: |
| Previous all-stream extradata | 1.70966 | 108,735,937 |
| Metadata plus selected-video extradata | 0.04393 | 11,809 |

Consumed metadata was identical. This benchmark included subprocess and JSON
handling, with the operating-system cache left alone. Its initial selected-video
query omitted the redundant `codec_name` field; production and the final harness
include it. The byte count above belongs to that recorded experiment, not an
exact byte prediction for every production response.

A separate no-attachment control measured 0.00519 seconds before and 0.01030
seconds after: about 5 ms additional work in this small fixture. The second
process is a real tradeoff, not a universal probe speedup. Large files, slow
storage and different layouts may behave differently. Non-HEVC input does not
need that second query. Cancellation of either subprocess is covered locally.

Reproduce with `python3 -B Scripts/benchmark_attachment_probe.py` followed by an
explicit development FFmpeg path and optionally `0` for the no-attachment
control. Records: `.build/performance/run.xgi2vhww/measurement.json` and
`.build/performance/run.6h49by46/measurement.json`.

## Validation and evidence identity

The complete `Scripts/check.sh` finished successfully with strict Swift 6 and
warnings-as-errors. It used bundled Python 3.13.15, the pinned FFmpeg 9.0.1
engine and verified Node 24.19.0. Log: `.build/preparation-review-check.log`.
The passing gate includes:

- Selected HEVC extradata, original stream selection, HDR/DV and track metadata.
- Cancellation and reaping during the second probe, plus the existing real
  bundled-process cancellation checks.
- Direct cache key dependencies, OCR identity, rejection/rebuild, cancellation,
  Off and clear while sessions retain their media.
- Existing HLS cache corruption, bounds, eviction and cancellation coverage.
- Both routes' command/metadata tests and shared subtitle staging regressions.
- The preceding terminal-cue correction and repeated bitmap-cache selection.
- Localization, publication-content checks, strict app build and distribution
  regression checks. Capture-tool tests are synthetic; no device was opened.

Base commit: `a475fcd92294c7054e75473d2e8b825b11f15446`, with the uncommitted
candidate on `codex/subtitle-eof-cache-review`. The locally built executable
SHA-256 is
`5e5bb2f288b4c71620895fbce4db1a00c1f10b533f6e0383d2e5cf9370c7a402`.
Production source identities:

| Source | SHA-256 |
| --- | --- |
| MediaProbeService.swift | `5e187989c93fee3f1d8aa51077a85bca5aa20da4f5d1bdfc3cf4684e95351704` |
| PGSSubtitleConverter.swift | `672d719e35b297010ed3e0877d6f9a5dbf06bb56c11216fb774407ecb9ef9a1f` |
| PreparedMediaCache.swift | `e296d9c3e15e0d05aecac8efb2344b10102c8b60f7b349c6dc10ec164a3be32e` |
| DirectPreparationCache.swift | `65d1bf3e8c7144a95047a532e142472c73457b605031650558d2e0783d6e093e` |
| StreamCoordinator.swift | `b62c640aa19bfc5eaaa901fc8fd48e259adea70241e6a55af430c6ec0f4bf376` |

After this passing gate, only this report and the benchmark harness's optional
no-attachment control were updated. The control itself passed; production and
test inputs to the app build did not change. No second identical build is needed.

## Experiment failures and cleanup

An initial guard invocation used the wrong callback shape and was corrected.
An early fixture attempt relied on a generator filter absent from the minimal
bundled engine; subsequent fixture generation uses an explicitly named
development encoder. These failed attempts are not accepted measurements.
The leftover 24 MiB synthetic attachment was removed. Generated Python bytecode
was also removed after the publication check rejected it; benchmark entry points
now disable bytecode generation. The later publication check passed.

Storage-guarded runs preserve reports and remove generated media. Final observed
test storage was 1.64 GiB. No personal films or installed applications were changed.

## Pending acceptance

This is locally validated implementation, not a release or receiver pass.
When the Apple TV is available, use a scoped batch to check:

1. Cold then warm direct HDR/DV MP4 playback with original compatible audio and
   selectable subtitles, including a track/settings change that must miss cache.
2. Bitmap subtitle preparation and the terminal cue on both direct and HLS
   routes. Preserve the previously declined end-of-track check as pending.
3. Shared probe behavior on both paths with the selected video, audio and
   subtitles intact. Combine observations with the above cases where possible.

The isolated runner must explicitly enable a private direct cache before a warm
hit can be claimed; its default direct test currently bypasses caching. Do not
use or clear the ordinary application's cache for testing. Settings text was
updated in both languages; its live layout has not been inspected in this turn.
Publication, installed-app replacement, whole-film reliability and physical
HDR/Atmos output remain unverified and outside this turn's authorization.

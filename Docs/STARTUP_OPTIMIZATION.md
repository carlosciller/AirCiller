# Playback startup optimization

## Scope and delivery

Phase 1 is local implementation and preparation. The baseline is `558b2350cec9414cfb1d8aca72a693f5412497ef`, after the 0.12.6 release and its CI correction. This candidate does not change the app version, installed app, bundled engines, AirPlay authentication or receiver commands. It has not been published.

Phase 2 will measure and verify the candidate on Apple TV before versioning, publishing or installing it. Local preparation measurements do not establish first visible picture, first audible content or whole-movie reliability.

## Changes in this candidate

### Reuse finalized HLS media

`PreparedMediaCache` retains the finalized video/audio renditions before session-specific subtitle and master-playlist work. A matching preparation reuses immutable media through hard links and copies the small playlists. Subtitle selection, subtitle delay and resume position do not invalidate this base. Changing the source, selected audio, audio output/delay, packaging parameters or bundled executable does.

The cache checks source identity again before admission and checkout. Its manifest admits only local finalized rendition files. Invalid entries fall back to preparation; failure to remove a partially checked-out link aborts that preparation, so FFmpeg cannot overwrite retained media through a hard link. Session playlists have separate storage because subtitle alignment may modify them. Playlist integrity uses SHA-256; cached media checks use file size and nanosecond modification time. This avoids rereading entire movies on checkout but does not detect arbitrary payload changes that preserve those attributes.

Settings > Storage exposes retained size, a limit and a clear action. The default is 16 GiB, with Off, 4, 16, 32 and 64 GiB choices. Oversized packages are not retained. Reducing the limit removes least-recently-used entries. This is a retained-cache budget, not a cap on the active movie's temporary working space. Media already linked into an active session remains usable after cache eviction. Reuse across different volumes is skipped instead of copying the full movie.

Direct HDR MP4 with subtitles is not cached or repackaged differently in this phase. Original media is never a cache entry and is never removed by cache controls.

### Overlap independent HLS work

Text and ASS extraction run alongside base video/audio preparation. Subtitle segmentation still waits for the final aligned video timeline. A throwing task group cancels and joins the sibling on failure. The coordinator defers deletion of an actively preparing HLS directory until its owning task has joined the children.

PGS/VobSub OCR keeps its existing sequence. Its final cue and cache identity can depend on the exact final video duration. Parallel bitmap extraction needs a separate design; using a probe estimate here would change timing behavior.

### Remove redundant waits and reads

HLS preparation awaits FFmpeg's termination event directly. A separate progress observer sleeps between UI updates but does not delay completion. It is cancelled and joined on success, error and cancellation.

Starting HLS cancels the source packet-demand scan. The final demand profile already comes from the prepared segment sizes. The direct MP4 route retains its existing demand analysis. This avoids an additional full source read competing with HLS packaging; its benefit on slow storage still needs measurement.

### Record useful timings without a live dashboard

The local diagnostic export includes monotonic HLS stage timings and cache-hit status. The current scope starts at preparation, after analysis and authorization, and ends when a receiver media request is observed. It does not call that request a displayed frame. Overlapping stages are recorded independently and must not be summed as elapsed time.

The trace contains stage names, relative durations, monotonic origin and a random attempt ID. It contains no media title/path, receiver address, credential or captured content. Stale callbacks cannot close stages belonging to a replacement session.

## Local measurement and validation

Completed on 11 September 2026 on arm64 macOS 27.0 (26A428), Apple Swift 6.4, deployment target macOS 14, optimized benchmark builds. `./Scripts/benchmark_startup.sh 5` generates a deterministic 18-second H.264/AAC fixture with embedded SRT and ASS. It rotates the comparison order and retains each measurement, stage trace, output inventory and source/engine hash. An existing development FFmpeg is used only to generate synthetic input; remuxing, probing and preparation use the pinned bundled engine. The benchmark never installs dependencies or opens devices.

Results below are milliseconds, five runs per cell. The [individual samples](Benchmarks/hls-startup-phase1.json) preserve all 40 measurements and scope limits.

| Preparation | SRT median (min/max) | ASS median (min/max) |
| --- | ---: | ---: |
| Frozen baseline, sequential | 236.089 (231.436/241.820) | 232.455 (229.170/242.414) |
| Candidate, cache disabled | 33.636 (33.247/35.164) | 33.531 (31.595/34.635) |
| Candidate, empty app cache | 39.815 (38.726/40.779) | 40.291 (38.818/41.015) |
| Candidate, prepared app cache | 21.243 (19.784/21.843) | 21.297 (20.991/21.654) |

Every served file and the final duration were equal to the frozen baseline in all 40 cases, checked with SHA-256 and direct byte comparisons. Generating the fixture independently twice produced the same SHA-256: `1c08197e86f59de82f0f2726114b8be0e8ca32df43a27f633c990f4595202cbf`.

The roughly 0.2-second saving is dominated by removing the baseline's 200 ms polling floor. Retaining a first package costs about 6 to 7 ms more than the cache-disabled candidate on this fixture. Warm reuse avoids video/audio preparation but still extracts the selected text track. These measurements do not predict savings for large movies, slower external drives, bitmap OCR, HDR, direct MP4 or the complete Play-to-picture interval. Five observations do not establish a reliable production tail-latency percentile.

The measured endpoint is complete local HLS preparation. Probing, cache fill for warm runs, first-use Settings budget enforcement, HTTP/AVPlayer/AirPlay startup, capture setup and output comparisons are outside that interval. The app's exported trace includes preparation-time budget enforcement in total elapsed time. App-cache state and operating-system cache state are distinct; no OS-cache purge was performed. CPU, peak memory and first captured picture/audio are still phase-two measurements.

### Checks and candidate

`./Scripts/check.sh` passed with exit 0, including strict Swift 6, warnings-as-errors, regression tests, real local Vision checks, the opt-in runner typecheck, publication-content checks, optimized app build and strict bundle signature verification. The new focused tests cover cache budget application/retry, collisions during checkout, cancellation of active children, failure of either preparation branch and absence of late progress callbacks.

Direct MP4 preparation and its command-builder method compare byte-for-byte with the baseline source. Pinned runtime files and release metadata are unchanged. The app build is 154,422,479 logical bytes, below the existing 165 MB budget; the cache lives outside the app bundle.

Private reproducibility artifacts remain under `.build/`:

- `startup-phase1-check.log`, SHA-256 `52653973dc1de9b6bf3fbc12ec5f98695163bf3c2717358907ab883be17cb02a`.
- `startup-benchmark/run.84Zj8l/`, including traces, bytes and the frozen baseline sources. Raw summary SHA-256: `fc311c0bdbd60e43b7919cfe235be030d94855aec636e3cf5b03e3aba2791dca`.
- Candidate `.build/AirCiller.app`, executable SHA-256 `49b1e9022d2577f4f4e04b948b759af836cd633e0f0d6211fbc795682da77aaa`. It retains development version 0.12.6 (59) and must not be confused with the released build.

The installed 0.12.6 executable remains `5571459ffba6a1285c8257f3a5dd85dd16eb5f971b40a0187e3c3af0930e4514`. No receiver test, installation, release upload or update-feed change was performed. The Settings interface is compiled and its preferences tested; its interactive review belongs to phase 2.

Local evidence completed:

- Strict Swift 6, warnings-as-errors, formatting and `./Scripts/check.sh`.
- Original baseline versus candidate served-file byte comparisons for text/ASS HLS.
- Empty, warm, disabled, oversized and invalidated cache cases, independent playlist storage and active-session survival after eviction.
- Running-process cancellation, sibling failure, cleanup and stale trace events.
- A review showing direct MP4 packaging and pinned runtime files unchanged.

## Phase 2 checklist

1. Freeze a candidate hash and preserve the installed 0.12.6 rollback. Confirm receiver availability; use only the explicitly authorized Apple TV screen/audio source, never a Mac or iPhone camera or microphone.
2. Measure baseline and candidate in alternating repeated runs on the same hardware/media. Record cache/connection state and capture setup separately. Include short and large inputs and slower external storage. Use known visible and audible opening cues.
3. Test HLS with no subtitles, embedded/external text, ASS, PGS and VobSub. For matching base reuse, change subtitles, delay, selected audio and resume position; confirm picture, sound, timing, complete duration and selectable tracks.
   The existing playback-check build disables the persistent movie cache. Before this phase, give its performance profile an isolated disposable cache and explicit empty/warm modes; do not claim warm-cache coverage from the existing cache-disabled runner.
4. Check cancelled preparation, immediate replacement, rapid controls, long pause/resume, end-of-movie transition, stop and replay. Include a direct HDR/Dolby Vision MP4 reference run without changing that packager.
5. Report individual times, median/tail, regressions, first captured picture/audio, early buffering, CPU/memory and temporary storage. Do not extrapolate short-fixture preparation gains to a full movie or call a warm cache a cold start.
6. If acceptance passes, select the release version, reconcile release notes/changelog with this record, package and sign, verify GitHub checks, publish and install with rollback. Failed or incomplete physical evidence leaves publication pending.

## Deferred work

Direct MP4 preparation optimization, reusable text extraction across attempts, staged bitmap decoding/OCR, probe reuse for bitmap transport origin/canvas, and connection/HTTP buffering changes need separate measurements. Consecutive bitmap deduplication and bounded OCR concurrency already exist and are not gains introduced here. Progressive or partial VOD would change a playback invariant and is outside this candidate.

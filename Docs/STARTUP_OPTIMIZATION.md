# Playback startup optimization

## Scope and delivery

Phase 1 covered local implementation and preparation. The baseline is `558b2350cec9414cfb1d8aca72a693f5412497ef`, after the 0.12.6 release and its CI correction. Phase 2 prepares version 0.13.0 (60), with the installed app unchanged until acceptance. Bundled engines, AirPlay authentication and receiver commands are unchanged.

Phase 2 verifies the candidate on Apple TV before publication or installation. Local preparation measurements do not establish first visible picture, first audible content or whole-movie reliability. The receiver record below includes successful checks and an audio-delay failure found during acceptance. The maintainer explicitly deferred that pre-existing defect's repair; it is excluded from this release.

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

## Phase 2 local preparation and resources

On 12 September 2026, `./Scripts/benchmark_startup.sh 4 large` compared the same frozen baseline with the candidate using a 2,218,226,312-byte synthetic H.264/AAC input. It was created by losslessly repeating the short fixture 160 times; the final packaged duration was 2,883.308 seconds. Four repetitions rotated all four modes through every position. All 32 cases matched the baseline's complete served-file inventory, SHA-256 hashes, direct byte comparisons and final duration. The [individual measurements and resource limits](Benchmarks/hls-startup-phase2-large.json) are retained.

Times below are milliseconds, median (minimum/maximum), ending at complete local preparation:

| Preparation | SRT | ASS |
| --- | ---: | ---: |
| Frozen baseline, sequential | 1,896.952 (1,888.356/2,156.020) | 1,917.445 (1,899.014/1,953.206) |
| Candidate, cache disabled | 1,583.488 (1,553.435/1,619.725) | 1,593.852 (1,540.021/1,661.526) |
| Candidate, empty app cache | 1,929.657 (1,897.898/1,961.815) | 1,967.717 (1,913.460/2,056.000) |
| Candidate, prepared app cache | 1,158.925 (1,144.466/1,168.559) | 1,161.703 (1,144.388/1,237.650) |

With cache disabled, preparation saved 313 to 324 ms. Warm reuse saved 738 to 756 ms. First admission into an empty cache was **slower** than the baseline: 32.705 ms for SRT (1.7%) and 50.272 ms for ASS (2.6%). The median `cacheStore` span was approximately 335 ms; warm `cacheLookup`, including checkout checks, took 666 to 669 ms. These overlapping stage spans must not be added together. Cache admission also increased the benchmark process's CPU use: median self CPU was about 0.7 seconds for the baseline and 1.4 seconds for first admission, while child CPU remained approximately 1.8 to 1.9 seconds. Warm runs used approximately 1.0 seconds of self CPU and 0.2 seconds of child CPU. First-use retention is therefore a tradeoff, not an unconditional startup improvement.

RSS was sampled for the benchmark process and its direct children, requesting a sample every 20 ms. Maximum observed aggregate RSS was 338 to 340 MB for baseline, 355 to 356 MB without cache, 354 to 355 MB with an empty cache and 42 to 43 MB for warm reuse (decimal MB). Across 2,213 sampling rounds, six process-info reads failed. By mode, the failed-read counts for SRT/ASS were baseline 0/2, disabled 1/1, empty 2/0 and warm 0/0. The JSON retains these per-mode counts; individual resource samples remain in the private artifacts. Sampling can miss peaks; summed process RSS can count shared mappings more than once and is not physical memory footprint. CPU and sampling overhead are included, not subtracted.

At preparation completion, served files occupied approximately 2.219 GB of logical file size. With retention enabled, served and cache paths summed to approximately 4.437 GB, but deduplicating hard-linked inodes yielded approximately 2.219 GB. The 2.218 GB source is separate. These are endpoint logical sizes, not peak temporary storage or allocated APFS blocks.

The campaign used internal storage with no OS-cache purge. No external data volume was available, so slower external storage remains untested. Generation, probing, warm-cache fill and output comparisons were outside the measured interval. Four observations do not establish a production tail percentile. This preparation-only harness does not measure the coordinator's cancelled packet-demand scan, bitmap OCR, direct HDR MP4, receiver startup, first picture/audio or full-film reliability. A separate corrected-resource smoke also passed all eight short-fixture cases; its one observation per cell is not another comparative campaign.

Private artifacts remain in `.build/startup-benchmark/run.eoolMh/`, including per-run traces, parity proofs, source and engine hashes, and representative outputs. Raw `summary.json` SHA-256: `3b61b05253a362411c39d18a9b1e7a19491c7d57cff7e2a20cbfeb16bb7c9f01`; `source-and-engine-sha256.txt`: `ed072db8e31082fb3e65e4eea277c72b3d69ceb0f2036ddcff1918b044d60b86`. Earlier resource-instrumentation trials were discarded from these results after correcting child-PID enumeration and benchmark hashing allocations; their JSON remains available. The final insufficient-space error wording changed after measurement; it did not alter the measured successful preparation path. No Apple TV test is established by this section.

The complete phase-2 `./Scripts/check.sh` gate passed with exit 0 after these changes. Its log SHA-256 is `0be52c6fbd98a5eb47c18f28b295f3ba4cb1bbb53608854f08c166dc6772d85b`. The ordinary staging app remains 0.12.6 (59), is 154,431,176 logical bytes and has executable SHA-256 `308f1467886c38bdfe62d741748a0212c832194b90587a4cf5e7d4ca1ca3f4dc`. The installed executable remains `5571459ffba6a1285c8257f3a5dd85dd16eb5f971b40a0187e3c3af0930e4514`. Subsequent receiver checks are recorded below. Full acceptance, publication and installation remain pending; this gate does not validate the later draft audio-delay repair.

## Phase 2 receiver checks, 12 September 2026

The tested checker executable is `0ab119a6a5c60de2ab8eaae4a59b38b1b94f1b2881ca08a00e78c17620845622`, built from the phase-2 preparation code. The separate offline startup evaluator passed the full strict gate; its gate log SHA-256 is `c59346e8841254f47c97e65cdb5c38ae8d031f36321a29f360aad6c2cf74a121`. Neither app version nor the daily installed copy has changed.

The maintainer confirmed receiver availability. All output checks used only the previously authorized Apple TV screen/audio source, with identity checks and no fallback to a Mac or iPhone camera or microphone. Credentials remained in their existing store; no pairing or permission reset was performed.

Completed captured-output checks:

- Direct HDR reference, HLS with external text subtitles and HLS without subtitles: all three passed controls, sampled motion, digital audio and the applicable subtitle-presence checks.
- HLS subtitle replacement, original audio-track selection and subtitle removal: each playback phase passed. The synthetic source's 880 Hz and 440 Hz tracks were distinguishable in the captured audio.
- Stop during active preparation passed cancellation and cleanup without delayed playback. A direct HDR natural end triggered exactly one HLS Playlist transition, with separately observed output before and after.
- HLS stayed paused for 360.063 seconds, then resumed in the same session at the requested position. Captured motion, digital audio and subtitles passed before and after the hold; cleanup was confirmed.
- Embedded SubRip and ASS both passed with subtitle stream index 2, not an external subtitle. Their synthetic movie derivatives retained identical original video/audio payloads. These simple ASS cues do not certify every animated effect or layout.
- External PGS and VobSub both passed controls, motion and non-silent digital audio. Review of saved initial and later post-seek frames found the expected text without clipping. Early post-seek frames still showed the known brief subtitle gap. This is not a claim of immediate subtitle recovery or a fresh OCR cache miss.

The isolated cache scenario did **not** pass. Cold preparation, warm replay, subtitle replacement, subtitle delay and original audio-track replacement had the expected cache misses/hits. Changing audio delay to +0.5 seconds correctly missed the cache and ran preparation again, but produced media identical to the unshifted alternate audio. The scenario stopped with `cacheMismatch` and confirmed cleanup; subsequent phases were not executed. A focused reproduction with the unchanged baseline command builder established that separate audio/video HLS outputs already discarded this offset before the optimization. The failed run is retained, not relabelled as a pass. Repair was initially included in acceptance, then explicitly deferred by the maintainer on 13 September after the failures below.

The first basic HLS capture could not establish startup latency: it had only one silent audio sample before Play and a 1.25-second gap during startup. Its output pass remains valid, while the separate timing report is inconclusive. No Apple TV startup speedup is established by those samples.

A fixed four-run comparison subsequently used baseline, candidate, candidate, baseline order, the exact same 60-second synthetic movie and fresh subtitle identifiers. Candidate runs each used a new isolated cache and attempted first admission; baseline runs had no prepared-media cache. Two seconds of capture preroll preceded Play in each case. All four controls/output checks passed, but all four onset assessments remained inconclusive. Each had an unobserved audio interval during startup; a candidate run also lacked the required consecutive fresh-pattern frames before the first control action. Missing samples do not establish either silence or a playback failure. No end-to-end timing gain, median or tail percentile is reported. This bounded campaign was not repeated to obtain a successful timing result. Individual reports and hashes remain in `.build/startup-phase2/paired-startup-ohb7e95o/`.

Private evidence directories: `playback-checks/capture-run-ovsncv0f` (basic), `playback-checks/capture-run-vfyl_pro` (failed cache scenario), `playback-checks/capture-run-zzg8n5bx` (track changes, cancellation and Playlist), `startup-phase2/bitmap-run-p4qpgd7l` (bitmap reports plus visual review), and `startup-phase2/embedded-text-run-pn4uzffu` (embedded text), all under `.build/`. Reports retain checker, input and capture hashes. Captured digital output does not establish physical speakers, Atmos layout, HDR panel rendering, physical-remote operation or whole-movie reliability.

The long-pause evidence is in `.build/playback-checks/capture-run-ab4_i4fd/`. The first draft audio-delay repair was not accepted: preserving the audio/video offset also required aligning subtitle time maps and ensuring the playlist covers the actual first and last media timestamps. Work paused for a maintainer decision; the installed app was unchanged. The Mac was locked at that checkpoint, preventing Settings review although receiver tests worked.

## Follow-up acceptance, 13 September 2026

The maintainer asked to finish the delivery, including the recommended timing repair, and confirmed the Apple TV was free and the Mac unlocked. The [audio-timing record](HLS_AUDIO_TIMING.md) tracks the correction and its distinct acceptance checks. Direct MP4 and the existing HDR HLS timing policy are preserved; the repair targets nonzero SDR audio adjustments.

Native Storage was inspected in the ordinary development candidate, 0.12.6 (59), executable SHA-256 `2f9c9362d47e87c96e7a6f4d0f5458227feb739be1852a86bc134b2d965da757`. Both English and Spanish interfaces showed the separate movie cache, subtitle cache and temporary-remnant sections. The empty movie cache disabled Clear; selecting 4 GiB, Off and 16 GiB updated the displayed values. Scrolling reached the lower controls without clipping. The original 16 GiB limit and app language were restored and verified after the user-approved temporary English check. Existing subtitle data was not cleared. These idle UI observations do not establish busy-state disabling, nonempty-cache deletion or displayed I/O failures; storage operations have separate deterministic tests.

The full application gate passed with the SDR repair sources. The ordinary candidate executable is `236fcbc65cddba2c08962f80efc85aa9304cb97b86017fcadc428a54e5d3a68b`, 154,803,915 logical bytes. The gate log SHA-256 is `8cec9e042b92e8410d91b237d4e5279eb6e1f08e3bf278ca4a50bb68c155cb61`. The test-only integer-seek correction and capture-reporting change were made later and need the final gate; this does not certify them retroactively.

Two nine-phase cache runs used checker executable `8d7816dfea1e999ae01090d9aecf6b3344e7e786d7b33c68b3fa12416a7dad0d`. Both completed receiver/control checks, expected cache hits and misses, immutable-base comparisons and isolated cleanup. Both complete output reports remain inconclusive because some capture windows lack enough samples. Retained offline reassessments establish each of the nine phases' sampled output in at least one run, with the same strict criteria; neither entire batch is relabelled as passed. Private evidence is under `.build/playback-checks/capture-run-ei69zp49/`, `capture-run-ydh46xr5/` and `.build/startup-phase2/cache-window-reassessment-20260913/`.

The subsequent +5-second audio-tail check failed. Checker executable `696b954537def093ad7f847a1b4f811a97d579340474a16ddbe36255874130ed` received the correct 64.995-second duration and confirmed the integer seek to 56 seconds. An incoming end notification arrived approximately four seconds later. The session teardown then prevented observation of the remaining audio. The [audio-timing record](HLS_AUDIO_TIMING.md) separates that failure from the earlier fractional-seek test defect and records the next diagnostic. Raw evidence remains in `.build/startup-phase2/audio-delay-tail-run-rfvhmo9p/`; no publication or installed-app replacement followed.

## Final scope decision, 13 September 2026

The maintainer approved closing the optimization separately from manual audio synchronization. Experimental audio packaging, subtitle timeline, cache-format changes and their test-only profiles were removed. Seven affected production/localization/test files were restored byte for byte to commit `1ba6a396b610db573c6191c55096a2115a3f26b0`, which already contains the startup optimization. Reversible patches and the experimental real-media test remain outside the release tree. The [audio investigation](HLS_AUDIO_TIMING.md) retains the failed checks and the unresolved design question.

The final cache scenario has seven phases, all with zero manual audio adjustment: cold preparation, warm replay, subtitle replacement, original alternate audio, subtitle delay, original audio restored and subtitles off. The capture criteria remain unchanged; each stable observation is extended to eight seconds to collect sufficient samples. The fresh final gate and receiver run passed after this scope change. Earlier incomplete batches remain incomplete.

Evidence reuse was checked against commit `6b8c0c4`, the production source of checker `0ab119a6a5c60de2ab8eaae4a59b38b1b94f1b2881ca08a00e78c17620845622`. `Sources`, `Resources`, the credential service, normal AirPlay helper, build script and locked dependencies have no diff in the restored candidate. Only release metadata and test tooling differ. The successful basic routes, track changes, cancellation, Playlist transition, six-minute HLS pause, embedded SubRip/ASS and bitmap output observations above remain applicable within their recorded limits. They are carried-forward observations, not newly executed device tests. The experimental nine-phase reports are excluded from acceptance of the restored package; the new cache sequence needs its own complete result.

The final `./Scripts/check.sh` passed for version 0.13.0 (60). Log SHA-256: `ca6b07fa4486c29061fd9c9389a6b41ff65060b5f11a9292975c7883f1a9cdc4`; ordinary local executable: `39d3a99296879dbc171b7eb3abaa507c2083c1d4443bd51af923c90ef8e5add3`. This includes strict Swift 6 compilation, cache ownership/invalidation/space-pressure tests, playback-check type checking and publication audit. The preceding attempts remain recorded: sandbox access to the pip cache stopped the first before tests; the next completed code tests but rejected one documentation phrase and generated Python bytecode. Both publication issues were corrected before the complete passing run.

The final receiver batch passed in 96.410 seconds with checker `e76e95a66e852d2a959ffb6f888fa9cc6b96468045d94bc8c70f47b7b73fc2de`. All seven windows passed sampled motion, expected original audio tone and expected subtitle presence or absence, with no evidence gaps. Cold and alternate-audio preparations missed the cache; the other five hit it with matching immutable media. Stop, session cleanup and disposable-cache cleanup were confirmed. The established noninteractive credential service and normal AirPlay helper hashes were unchanged. No Mac or iPhone camera or microphone was used.

Private report: `.build/playback-checks/capture-run-0rqjiw2c/report.json`, SHA-256 `81e4195e5ebd97c896042769198536f49abf7565b49a6aebc5f11493189294c8`; controls SHA-256 `7e01574f169f720674fe8e4b817e86ca4dd032e32d17154d87b6a4b5d4bb9963`. Each window contains 10 to 14 frames and 34 audio measurements. These observations establish bounded output and cache behavior. They do not establish frame-accurate subtitle delay, physical speaker layout, whole-movie reliability or a faster Play-to-picture endpoint.

This completes code and bounded playback acceptance for the optimization-only delivery. Native Storage was checked in both languages as recorded above. External storage and end-to-end startup timing remain unmeasured; the release makes only local-preparation and reuse claims. Packaging, exact-commit GitHub checks, signed assets and actual update/install are separate release steps under [Distribution](../DISTRIBUTION.md), not inferred from this acceptance record.

## Phase 2 checklist

Phase 2 preparation found and corrected a disk-pressure regression: retained HLS entries could consume space needed to prepare the next movie. A cache miss now attempts bounded, least-recently-used eviction on the preparation volume before failing the space check. Actual available capacity is reread after each removal and before the final decision, including cleanup-error paths. A removed entry whose media is still linked into an active session is not assumed to have freed its payload. Focused tests cover these cases; final bounded receiver acceptance is recorded above.

The opt-in playback checker supports a disposable HLS cache. The earlier eight- and nine-phase experiments are retained in the historical record above. The final seven-phase sequence checks immutable base reuse and invalidation without the deferred manual audio adjustment. Reports record monotonic request/receiver timestamps and verify base hashes. These are verification hooks, not changes to daily playback or a clean startup benchmark.

1. Freeze a candidate hash and preserve the installed 0.12.6 rollback. Confirm receiver availability; use only the explicitly authorized Apple TV screen/audio source, never a Mac or iPhone camera or microphone.
2. Measure baseline and candidate in alternating repeated runs on the same hardware/media. Record cache/connection state and capture setup separately. Include short and large inputs and slower external storage. Use known visible and audible opening cues.
3. Test HLS with no subtitles, embedded/external text, ASS, PGS and VobSub. For matching base reuse, change subtitles, delay, selected audio and resume position; confirm picture, sound, timing, complete duration and selectable tracks.
   Use the checker's isolated disposable cache and explicit empty/warm expectations; the ordinary cache-disabled profile does not establish warm-cache coverage.
4. Check cancelled preparation, immediate replacement, rapid controls, long pause/resume, end-of-movie transition, stop and replay. Include a direct HDR/Dolby Vision MP4 reference run without changing that packager.
5. Report individual times, median/tail, regressions, first captured picture/audio, early buffering, CPU/memory and temporary storage. Do not extrapolate short-fixture preparation gains to a full movie or call a warm cache a cold start.
6. If acceptance passes, select the release version, reconcile release notes/changelog with this record, package and sign, verify GitHub checks, publish and install with rollback. Failed or incomplete physical evidence leaves publication pending.

## Deferred work

Direct MP4 preparation optimization, reusable text extraction across attempts, staged bitmap decoding/OCR, probe reuse for bitmap transport origin/canvas, and connection/HTTP buffering changes need separate measurements. Consecutive bitmap deduplication and bounded OCR concurrency already exist and are not gains introduced here. Progressive or partial VOD would change a playback invariant and is outside this candidate.

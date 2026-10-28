# Direct MP4 preparation and concurrent demand analysis

## Scope and selected checks, 23 October 2026

This is a measurement-only follow-up to the
[library cache baseline](LIBRARY_STARTUP_MEASUREMENT.md). Reference commit:
`212ad23d825268543c0123874c7838ecca41a4c6`. Application sources, runtimes,
dependencies, settings, ordinary caches and installed app remain unchanged.
The changed tracked files are documentation only. The diagnostic harness is
retained privately with its source snapshots and input hashes.

Required checks are strict optimized compilation of the diagnostic, actual
analysis-process overlap, equivalent output hashes, source identity preservation,
completed resource observations and the documentation gate. The existing full
application checks remain applicable to the unchanged production inputs. There
is no receiver/control/UI change that requires an Apple TV or capture campaign.

## Controlled comparison

Two complete private-library HDR inputs, original compatible audio and selected
text subtitles. One input uses its embedded text; the other has only bitmap
subtitles and uses a short fixed external WebVTT for this experiment. OCR is
outside this comparison. Neither video nor audio is transcoded.

Three paired repetitions per input alternate the order: without/with analysis,
with/without, without/with. Every sample performs the same complete source-hash
read before its timing interval. This makes the comparison a warm-source-cache
experiment; no OS caches are purged and cold disk behavior is not established.
Direct MP4 does not use the HLS prepared-media cache.

The harness snapshots `makeDirectFileProcess` from the current coordinator and
links the unchanged command builder, demand analyzer, HDR injector and probe.
The copied process launcher gains one observational start hook. The concurrent
case waits for the actual `-show_packets` process to start and confirms it is
still running at mux start. The ordinary 200 ms process polling cadence is
retained, with UI updates omitted in both modes. That cadence limits precision
when interpreting small differences.

Preparation includes muxing, the existing conditional HDR static-metadata
injection, output probing, duration/HDR/audio/subtitle checks and direct-file
demand-profile construction. It excludes probing the source, source hashing,
post-preparation output hashing, HTTP/AirPlay/local-player startup and first
picture/sound. Analysis joins after the measured preparation interval; remaining
analysis time is recorded instead of being added to preparation latency.

Every output must have the same complete MP4 SHA-256 within its input group.
Each source is rehashed before every sample and has matching device/inode/size/
mtime/ctime records before and after the campaign. CPU and sampled RSS use the
existing monitor, whose 20 ms sampling can miss short peaks. Resource counts
cover the preparation interval, not the excluded hash passes. No unrelated
process is stopped or reconfigured to improve a result.

## Private evidence

The diagnostic sources live at `.build/direct-demand-tools`. The corrected
storage-guarded campaign is `.build/startup-benchmark/measurement-direct-708JJs`, with production
and generated-source hashes, pinned FFmpeg hashes, compiler/OS identity, private
input metadata and per-sample timings/resources. Generated movie payloads are
removed after their hashes are verified; reports and source snapshots remain.

## Excluded initial campaign

The initial campaign at `.build/startup-benchmark/measurement-direct-Wp0SlO`
completed all 12 samples and byte/identity checks, but is excluded from latency
conclusions. Its new streaming hash reader lacked the bounded autorelease pool
used by the existing library benchmark. The analysis case introduced an earlier
asynchronous suspension, so temporary hash-reader memory had a different lifetime
between modes. Without-analysis self RSS reached about 5.6 GiB, while concurrent
cases remained much smaller. The first memory snapshot is taken at monitor
creation, so even memory released at the following suspension enters that maximum.

The reader was replaced with the existing benchmark's one-MiB reads inside an
autorelease pool. Only this paired direct-route campaign was repeated; the
earlier HLS, cache, HDR/subtitle receiver and application test campaigns were
not repeated. Initial samples, generated-source snapshots and verification
results remain retained. They are not relabeled as an accepted speed result.
The corrected campaign also matches the initial campaign's source and output
hashes, confirming that the harness correction did not change prepared media.

## Corrected results

All 12 corrected samples passed overlap, byte parity, input-identity and resource
checks. Both source files are PQ HEVC with original audio: A is a full movie
with mono AAC and the fixed external text cue; B is an episode with E-AC-3 and
an embedded SubRip track. The campaign completed with exit 0 and its generated
movie payloads were cleaned by the storage guard. Production source hashes and
the extracted process-factory body were independently checked against the
unchanged checkout.

Seconds below are medians of three samples; output sizes include MP4 padding.

| Input | Output GB | Without analysis | With analysis | Paired changes, with minus without |
| --- | --- | --- | --- | --- |
| A, full HDR movie | 10.35 | 14.139 | 19.836 | +3.964, +6.743, +10.439 |
| B, HDR episode | 2.90 | 2.894 | 2.313 | +0.021, -0.183, -0.586 |

The median paired penalty for A is 6.743 s. This is different from subtracting
the two group medians (5.696 s), because those medians come from different
pair indices. A's without-analysis range is 8.327 to 15.872 s; its concurrent
range is 18.765 to 20.883 s. All three paired comparisons favor preparing alone.
B has overlapping ranges and mixed signs; there is no consistent penalty.

A's mux spans are 8.219 to 15.700 s without analysis and 18.578 to 20.833 s
with it. Header adjustment is 0.020 to 0.026 s and output probing 0.025 to
0.163 s. Direct-file profile construction is below 0.001 s. The measured
difference is concentrated in muxing, not metadata-header work or validation.
This experiment does not separate disk, CPU and scheduler contributions.

Analysis was running at mux start in every concurrent sample. Its head start
was 0.7 to 1.9 ms. It finished 7.2 to 11.1 s before preparation ended for A
and 1.9 to 4.0 s before preparation ended for B. Preparation timing therefore
does not include waiting for an analysis task after the output is ready.

The corrected benchmark's self RSS peaks are 77 to 85 MiB in both modes, with
sampled aggregate peaks around 144 to 170 MiB. There are no failed RSS queries
in the corrected campaign. A median aggregate CPU is 13.81 s without analysis
and 17.56 s with analysis; B is 2.08 s and 2.54 s. CPU counters include the
benchmark and its completed children. They do not describe whole-system load.
The Mac had 24 GiB of memory and macOS 27.2. A mid-campaign read in the excluded
run showed about 12.4 GiB of existing swap use; no baseline or causal attribution
to this experiment is established. Background activity and filesystem state can
still affect the size of a measured penalty. No system settings were changed.

The output SHA-256 values, identical across all six samples per input, are:

- A: `5e7263d1dd0d099b94ee450279c81ae01a556721cad51a9666bdfd33a1f964fb`.
- B: `853f70b78b5ad645a796f724c414e431c1db666425c3ee48ea4c35b5be7bde19`.

The independently verified `comparison.json` hashes to
`3ae4c47a72f12fca4b21d563c27b417eb6dd30a0b84139d3257e0b8fd380e8e3`.

## Decision and next candidate

The subsequent [28 October candidate review](REVIEW_2026_10_28.md) records the
implemented cancellation/join change, new comparisons and scoped acceptance.
The measurements below remain the original experiment, not a current release claim.

Concurrent full-file analysis can compete materially with direct preparation
for the tested large movie. A scoped follow-up should cancel or postpone only
unfinished demand analysis at direct preparation, while retaining an already
computed profile and an honest fallback for peak estimates. It needs ownership,
cancellation, source-change and diagnostic-profile regressions before release.
HLS already cancels this task at its preparation boundary.

The actual app starts demand analysis after source probing, before the user
presses Play. If that analysis has already finished, this contention is absent.
These deliberately aligned starts are not a prediction of every user startup,
first television image or transport latency. No segmentation, engine version,
quality policy, integrity check or production scheduling was changed here.

No unrelated HLS, receiver, subtitle/OCR or updater tests were repeated. The
corrected diagnostic compiled with optimized Swift 6 strict concurrency and
warnings as errors. The documentation gate and diff checks cover the only
tracked changes; the preceding accepted application tests remain applicable.
The installed executable remains
`045cea170ee54e8d192ec54b4e8c1b5f6ad31ba76218a628b04ab31f30e4726b`.

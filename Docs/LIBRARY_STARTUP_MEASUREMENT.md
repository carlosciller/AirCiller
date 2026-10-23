# Library preparation measurements, 23 October 2026

## Scope and validation selection

Reference: released 0.18.1, commit `5886feead4781f0df94164d39981382d14d728f5`.
Only benchmark tooling, testing documentation and the roadmap change. Production
sources, helpers, resources, locked runtimes and dependencies remain unchanged.
The benchmark compiles the actual production preparation/cache/demand services
with Swift 6 strict concurrency, warnings as errors and optimization enabled.
Validate the new wrapper and measurements locally, then run the required full
local gate once. Existing playback evidence remains applicable; no Apple TV,
capture, Keychain, installation or publication is needed for these tool changes.

## Method

Three complete private-library movies on the internal SSD, three repetitions
each with an empty cache followed by a warm checkout. The cache is isolated and
limited to 32 GiB; each repetition removes only its own generated session and
cache after recording served-file hashes. Original compatible audio is retained;
subtitles are disabled. Both SDR and HDR cases use the actual HLS preparation
service. This does not measure the separate direct MP4 path, subtitle extraction,
OCR, networking, television output or concurrent full-file analysis contention.

Probe and packet-demand analysis run separately before each preparation. Their
times must not be added to the preparation interval as a claimed Play delay.
The OS file cache is not purged, and full-file demand analysis reads the source
before preparation. Empty therefore describes the app cache, not cold disk I/O.
Before/after source size and modification date are checked within each movie run.
The finalized wrapper additionally records device, inode, size, mtime and ctime.
Source bytes are never written. Source integrity checks are outside timing.

Raw observations remain private under
`.build/startup-benchmark/measurement-library-4xHt68/media-{0,1,2}`.
All 18 sample JSON files contain stage spans, probe and analysis times, CPU,
sampled peak RSS and complete served-byte inventories. Sampling is every 20 ms
and can miss short memory peaks. Inventories are equivalent within each movie
across all six preparations. The harness verifies cache misses/hits explicitly.

## Results

Seconds below are medians of three samples. Sizes are decimal GB of served output.

| Input | Output GB / files | Probe empty / warm | Demand empty / warm | Preparation empty / warm |
| --- | --- | --- | --- | --- |
| A: SDR H.264, E-AC-3 | 20.92 / 2,647 | 0.029 / 0.031 | 4.829 / 4.939 | 21.781 / 2.279 |
| B: SDR HEVC, FLAC | 12.72 / 2,283 | 0.014 / 0.036 | 3.319 / 3.208 | 20.283 / 1.918 |
| C: HDR HEVC, AAC | 10.34 / 727 | 0.013 / 0.043 | 2.546 / 2.585 | 22.231 / 0.566 |

| Input | Empty packaging / admission / validation | Warm checkout / validation | Preparation CPU empty / warm | Sampled preparation RSS range empty / warm, MiB |
| --- | --- | --- | --- | --- |
| A | 20.551 / 0.954 / 0.232 | 1.998 / 0.238 | 16.49 / 2.26 | 1,722-2,253 / 18-21 |
| B | 19.279 / 0.860 / 0.214 | 1.687 / 0.209 | 11.18 / 1.91 | 882-1,036 / 16-19 |
| C | 21.876 / 0.280 / 0.016 | 0.542 / 0.016 | 7.79 / 0.56 | 831-964 / 11-21 |

Medians of individual spans need not sum to the median total. Empty preparation
ranges are 21.066-25.032 s, 18.291-21.476 s and 15.888-23.794 s. Warm ranges are
2.237-2.341 s, 1.883-1.971 s and 0.554-0.579 s. Paired controls are required
before claiming a small implementation speedup within this spread.

Across all six analysis runs per movie, median aggregate CPU was 5.533 s,
3.617 s and 3.645 s; sampled aggregate analysis RSS ranges were 29-62 MiB,
25-53 MiB and 26-37 MiB. Eleven process-RSS queries failed across the complete
campaign; all samples still have resource observations. Reported maxima are
sampled lower bounds, not certified peak memory. Raw query-failure counts remain
in every JSON record, including the failed queries.

The ordinary app preference was read as 16 GiB. A exceeds that admission budget;
its measured warm result requires the larger isolated experimental budget. B and
C fit individually. These observations do not promise a warm hit after eviction
or simultaneous retention of several movies. No user setting was changed.

## Link-operation experiment and decision

A separate alternating five-repeat experiment creates 2,647 links using either
Foundation or POSIX, verifies their bytes and removes only generated targets.
Results are retained under
`.build/startup-benchmark/measurement-library-mDP8V7/cache-links/samples.json`.
Foundation median: 0.962 s (0.903-0.978); POSIX median: 0.936 s (0.898-0.951).
The ranges overlap and a pair reverses direction. The roughly 27 ms median
difference does not demonstrate a worthwhile reduction in real checkout time.
This synthetic one-inode experiment is not a real-movie before/after result.

No production optimization is adopted. Cache already avoids full remuxing;
the remaining warm cost includes thousands of filesystem operations and retained
validation. Full-file demand analysis costs seconds, but HLS startup already
cancels that task. Removing it would not establish an equal startup saving.
Direct-route contention requires a separate paired scheduling experiment before
changing ownership or cancellation. Do not remove integrity checks, lower VOD
requirements or change segment policy to improve these numbers.

## Retained failure

The first library wrapper exited 2 after all 18 measurements completed. Editing
the shell wrapper while it was running left a trailing `-L` fragment that the
shell tried to execute. The storage guard recorded the failure and retained all
sample reports; it is not a successful wrapper run or a playback failure.
The subsequent links-only run completed with exit 0. The completed full wrapper
was checked separately on a short synthetic input; repeating all private
movies would add no measurement evidence for that wrapper correction.
The corrected `--self-test` run at
`.build/startup-benchmark/measurement-library-jY8TAi` completed with exit 0,
six matching inventories, expected empty/warm cache states and identical
before/after device/inode/size/mtime/ctime records. Its generated payloads were
cleaned by the guard, with reports retained. Only an unused resource-key request
was removed afterward; source size/mtime checks and measured code are unchanged.

## Final local acceptance

The strict local suite passed through all compiled tests and capture-tool
compilation in `.build/library-measurement-full-check-final.log`. Its publication
text check then rejected range dashes and two phrases in this report/roadmap.
After correcting only prose, the unchanged remainder of `Scripts/check.sh`,
starting at `check_publication.sh`, ran successfully in
`.build/library-measurement-remaining-check.log`. It completed the strict app
build, bundle-content assertions, signature verification and three packaged
Python tests, ending with `AirCiller local checks: OK`. Passed tests and the
private-media campaign were not rerun for the prose correction. The earlier
format-check failure is retained in `.build/library-measurement-full-check.log`.

An independent reread of all 18 sample JSON files confirmed matching inventories,
the expected cache states and recorded resource samples. The manifest of their
SHA-256 hashes is retained beside them; that manifest hashes to
`e2ee137eac1a7954ce6df54df338d23b726766010e0fcc859824fb58d28d92d1`.
The link experiment JSON hashes to
`5530bfce32c94240f3458bfe51e88f0f5d22387b4eb9e3e29cb537a31ae038a1`.
Read-only metadata inspection confirmed H.264/E-AC-3 5.1, SDR HEVC/mono FLAC
and PQ HEVC/mono AAC for A, B and C respectively.

`git diff` confirms no changes to production sources/resources, Info.plist or
the dependency lock. The daily installed executable retained SHA-256
`045cea170ee54e8d192ec54b4e8c1b5f6ad31ba76218a628b04ab31f30e4726b`.
No receiver session, publication, installation or ordinary-cache cleanup was
performed. This is accepted local measurement tooling and a documented decision,
not a new claim of television performance or a production speedup.

# Testing strategy

This guide defines current validation. Dated outcomes belong in the linked
records and [validation history](Docs/VALIDATION_HISTORY.md); an old pass is not
evidence that a different candidate has passed.

## Choose checks from the change

Follow [Contributing](CONTRIBUTING.md#minimum-validation). Identify the affected
behavior and applicable cases before testing:

| Change | Required validation |
| --- | --- |
| Documentation or agent instructions only | Review the diff and changed references; run `git diff --check`. No app build or playback session |
| Code, dependencies or build configuration | Meaningful regression coverage and `./Scripts/check.sh`, which includes the strict application build |
| Native UI | Inspect the changed interaction in the running app. Pure interface work does not require unrelated playback tests |
| A control that starts, changes or stops playback | Check its native interaction and affected playback behavior |
| One playback path | Local media checks and applicable receiver/output cases for that path |
| Shared session/control/server code, or an engine upgrade | Assess and validate affected behavior on both direct MP4 and HLS |

Before implementation, record a short validation selection: changed boundary,
required local checks, any receiver/output cases, and why earlier evidence can
or cannot be retained. A release number alone never invalidates playback evidence.
Keep this selection with the candidate report, not as a new permanent runbook.

Apply these narrower rules when choosing receiver cases:

- Interface, library, preferences and About links need no Apple TV session unless
  the changed behavior controls playback.
- Packaging-only cleanup needs bundle inventory, signature, import and launch
  checks. If retained functional files are unchanged, do not repeat HDR or subtitles.
- Classify dependencies by their actual callers. A secondary HTTP dependency is
  not automatically a media-engine upgrade. Test imports and the used HTTP/control
  boundary; add a scoped receiver smoke only for a changed or uncertain playback path.
- Changes to an audio/subtitle component need its regression and the affected
  route/case, not every codec and track combination.
- FFmpeg, pyatv, Python or shared transport changes need both routes assessed and
  short applicable playback checks. Long pause, natural end, rapid commands, OCR
  and cache campaigns are required only when those boundaries are affected.
- Check stop/replay/close briefly when playback was affected. Do not run an
  extended cache/track-change campaign merely to establish replay.

Reuse device evidence only after comparing relevant source, helpers/resources,
locked engines/dependencies, build configuration and media/track settings. Record
the original report and the comparison; do not label reused evidence a fresh run.

The matrix below is the playback case catalogue, not a requirement to repeat
every case for every release. An applicable case remains a release gate; a
failure or missing required observation must be resolved or explicitly left
pending. After playback validation, include stop, replay and app close.

Once the required checks pass, stop. Repeat or broaden them for new changes,
failures or unresolved concerns. Carrying earlier evidence forward requires a
comparison of the candidate's relevant source, pinned runtimes and build
configuration; it does not constitute a new device run. Publication and installed
updating are separate checks under [Distribution](DISTRIBUTION.md).

## Evidence levels

Record these separately. They describe what was observed, not four mandatory
rounds of testing for every change.

| Evidence | Establishes | Does not establish |
| --- | --- | --- |
| Local or simulated | Compilation, deterministic behavior, media structure, sample/packet conservation, local decoder behavior | Apple TV acceptance or output |
| Receiver | Events, reported progress, accepted control changes and session cleanup from the Apple TV | Visible picture, audible sound or subtitle output |
| Captured digital output | The approved Apple TV source supplied the sampled moving picture, digital audio and expected cues | Physical speaker routing, Atmos, HDR rendering or uninterrupted full-movie playback |
| Physical observation | What a person directly confirmed on the television and sound system, within the observed interval | Untested tracks, layouts, devices or an entire movie from a short sample |

Keep failed and incomplete reports alongside later results. A corrected offline
assessment must identify its inputs and changed evaluator separately; it must
not overwrite the original report or be described as a new capture. Repair
verification defects with a regression, not by weakening a criterion to make
the candidate pass.

## Deterministic checks

Run `./Scripts/check.sh` from the repository root. It validates formatting,
strict Swift 6 compilation with warnings-as-errors, standalone regressions,
Python bridge simulations, private relay/lifecycle Node tests, strict native
lifecycle-helper compilation, packaging and publication checks. The Node version
is fixed in `.node-version`; `AIRCILLER_NODE` may select that executable. It already builds
the application; do not repeat an identical build after it passes.

Tests use synthetic inputs and do not require private media. The suite builds
and typechecks the optional playback tools without opening a capture source or
starting an Apple TV session. The standalone tests it runs are listed in
`Scripts/check.sh`.

Push, pull-request and release-tag CI retain the required `build-and-test` job
on `macos-26`. It always runs policy regressions and reports one validation mode:

- `docs`: only allowlisted prose changed; check the diff and publication rules.
  Unknown paths, executable files and packaged release notes require the full gate.
- `full`: prepare pinned dependencies and run `./Scripts/check.sh` once.
- `reuse`: an immutable GitHub artifact proves a successful full run with the
  identical entire Git tree, runner image, OS, Xcode, Swift, architecture and
  selection-Python and Node versions. The summary links the originating run. Only completed,
  successful runs of this workflow from the same repository are eligible; expired,
  missing, failed, preview/manual or invalid evidence falls back to `full`.

No path-filtered workflow or skipped required job substitutes for acceptance.
Reused runs do not publish new full-check evidence. Artifacts expire after 30 days;
API failure or changed inputs means more testing, never automatic acceptance.
PR-to-main and main-to-tag reuse therefore works only when inputs really match.
Concurrent runs may both run the suite if neither has completed yet.

Manual `workflow_dispatch` always runs the full suite, including on `xcode-27`
for preview diagnostics. CI identity does not certify the locally signed release
artifact or replace applicable playback evidence. See the
[Vision CI investigation](Docs/VISION_CI.md) for why these environments are separate.

## Local tests with media

Executables and scripts that require a real file receive its path through an
argument or environment variable. Keep media and private reports outside Git,
normally under `.build/`. These checks can validate containers, OCR, local
AVPlayer behavior and finalized VOD playlists. They do not prove tvOS acceptance.

Choose the relevant media matrix from the validation records below. The audio
records distinguish packet copy, decoded-sample conservation, layouts, internal
timestamps, damaged input and cache reuse. A decoder exit status alone does not
prove losslessness. Use the pinned bundled engines for comparisons.

<a id="3-physical-apple-tv-matrix"></a>

## Receiver and output checks

The opt-in [playback check runner](Docs/PLAYBACK_CHECKS.md) uses an isolated build
of the real app and reports receiver controls separately from captured output.
Use its documented profiles and source-selection procedure. Never activate
Mac/iPhone cameras or microphones; capture only the explicitly approved, exact
Apple TV digital screen/audio source, with no default-source fallback. Stop if
that source cannot be guaranteed.

Select applicable cases from this catalogue according to the changed boundary.
Use separate evidence for the two media paths and distinguish command
acknowledgements from receiver-confirmed behavior.

| Path | Case | Expected result |
| --- | --- | --- |
| Direct MP4 | HDR/Dolby Vision, E-AC-3/Atmos, with selectable subtitles | Correct picture and tracks; synchronized duration and position |
| HLS/fMP4 | Without subtitles | Complete VOD, no live indicator or preparation pauses |
| HLS/fMP4 | With WebVTT | Selectable, synchronized subtitles that are not burned into the picture |
| Control | Long pause and resume from the remote | AirPlay remains linked and the Mac does not sleep automatically |
| Control | Natural end of the current item | The Apple TV confirms completion and the next Playlist item starts once |
| Control | Rapid pause, resume and seek commands from Mac, Apple TV Remote and iPhone Remote | Commands remain ordered, the timeline stays synchronized and AirPlay remains linked |

The runner covers a subset of these observations. Its automated commands do not
establish that a physical remote was used; digital audio capture does not certify
Atmos or physical speakers. Record that distinction. Do not ask the user to repeat
a check that automation has already established at the required level.

Keep the installed app intact until the applicable validation and distribution
gates pass. Retain a rollback copy when installing, as described in
[Distribution](DISTRIBUTION.md).

## Signed application updates

Follow [Distribution](DISTRIBUTION.md) for release authorization, CI, packaging,
signatures, appcast checks, native Sparkle installation and rollback. A build,
signed archive or successful download is not an installed-update check. Verify
the relaunched version separately from playback acceptance.

<a id="12-reproducible-performance-fixtures"></a>

## Reproducible performance fixtures

Run `./Scripts/benchmark_performance.sh` for optimized, synthetic measurements of ASS conversion and bounded process output. It reports all seven samples and their median, checks stable conversion and buffer output, and saves generated WebVTT alongside timings under `.build/performance/`. It does not use private media or install the app.

To compare an earlier implementation, pass a directory containing its `ASSSubtitleConverter.swift` and `ProcessDataBuffer.swift` as the first argument. Use the same compiler and fixture, run the versions sequentially, and compare their generated WebVTT with `cmp`. The fixture uses modern alignment; legacy SSA alignment is covered separately by the regression test because the original expression silently failed to compile.

These measurements cover 2,000 subtitle cues and 32 MiB of writes in 4 KiB chunks with a 1 MiB retained tail. They do not measure end-to-end playback, television compatibility, or battery consumption. The process buffer amortizes copying by retaining up to twice its configured byte limit internally; snapshots still expose at most the configured limit.

`./Scripts/check.sh` includes deterministic tests for buffer limits, compaction, retained snapshots, concurrent writes, legacy subtitle alignment, and concurrent conversions. Timing thresholds are intentionally excluded from CI.

The [startup optimization record](Docs/STARTUP_OPTIMIZATION.md) contains separate
preparation and end-to-end observations. Report cold preparation and warm cache
reuse separately; the benchmark does not reset the operating-system cache.
Further startup work follows the [roadmap](ROADMAP.md#faster-playback-startup).

For current HLS preparation, run `./Scripts/benchmark_startup.sh 3 small head`.
This freezes committed HEAD as the no-cache reference and compares it with the
working candidate, including empty/warm app-cache modes. The optional historical
reference remains available, but its older subtitles differ after the seek fix;
its strict parity failure must not be suppressed or used for a speedup claim.
The [October review](Docs/REVIEW_PLAYBACK_2026_10.md#benchmark-reference-repair)
records the baseline repair and current small-fixture samples.

For a private HLS preparation campaign, run
`zsh Scripts/benchmark_library.sh /absolute/movie ...`. It uses three paired
empty/warm isolated caches (32 GiB), original compatible audio and no subtitles.
Probe and full-file bitrate analysis are measured separately before preparation;
this does not simulate their overlap with playback startup. Served inventories
must match byte for byte across all repetitions. CPU and sampled RSS are retained
with stage timings. Originals and ordinary app caches are not modified. Private
paths and inventories stay in the ignored, storage-guarded run. The guard retains
reports and removes generated payloads. `--self-test` checks the complete wrapper
with an existing synthetic fixture generator; `--links-only` measures link APIs.
See the [real-library measurement](Docs/LIBRARY_STARTUP_MEASUREMENT.md) for scope,
the initial wrapper failure and why no production optimization was adopted.

## Validation records

Read the record relevant to the change, not every previous run. Each records its
own candidate, failures, observations and remaining limits.

- [October reliability, security and interaction review](Docs/REVIEW_2026_10.md)
- [Optional private control and lifecycle checks](Docs/PRIVATE_REMOTE_CONTROL.md)
- [Playback runner, capture and control checks](Docs/PLAYBACK_CHECKS.md)
- [PCM/LPCM and TrueHD audio conversion](Docs/AUDIO_EXPANSION.md),
  [SDR manual audio timing](Docs/HLS_AUDIO_TIMING.md) and
  [original FLAC soundtracks](Docs/FLAC_AUDIO.md)
- [Transport streams](Docs/TRANSPORT_STREAMS.md),
  [external PGS](Docs/EXTERNAL_PGS.md) and [external VobSub](Docs/EXTERNAL_VOBSUB.md)
- [Library and seasons](Docs/LIBRARY_SEASONS.md) and
  [native interface integration](Docs/NATIVE_UI_INTEGRATION.md)
- [Startup optimization](Docs/STARTUP_OPTIMIZATION.md) and
  [stability review](Docs/STABILITY_REVIEW.md)
- [Archived validation history](Docs/VALIDATION_HISTORY.md)

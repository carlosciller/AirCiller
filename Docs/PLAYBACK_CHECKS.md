# On-demand playback checks

This development tool drives the real `ContentView`, `StreamCoordinator`, packaged engine, AirPlay controller and HTTP server. It is compiled into a separate check application, not included in ordinary releases. It needs no extra Apple TV app.

## Current coverage

Each selected clip runs through analysis, original-audio eligibility, startup, pause, resume, a rapid +10/+10/-10/-10 sequence, resume again, and Stop. Pause and resume are explicit commands; a test does not toggle them based on potentially changing receiver state. The runner checks receiver-reported states and command acknowledgements separately. It also checks the expected direct MP4 or HLS output, actual media requests, released runtime references and temporary output, and surviving processes in the launcher's process group.

Some receivers report playing and paused states without positions, even after commands. The runner checks progress after the first resume, before issuing any seeks, since a receiver may supply its position only on resume. It checks seek destinations against fresh receiver positions too. Missing positions go into `unverifiedChecks`; conflicting positions still fail. It continues the batch when evidence is absent, but reports the overall result as `inconclusive`. It never substitutes the Mac's timer or the echoed seek target for a receiver position.

Optional scenarios cover changing tracks during playback, stopping an active preparation, natural completion followed by exactly one Playlist transition, and six-minute pauses. Hardware acceptance is recorded separately below, including the long-pause runs and the corrected evaluator. This runner is not the entire physical release matrix in [TESTING.md](../TESTING.md).

## One command with captured output

The capture workflow prepares its fixtures, checks noninteractive credential access, verifies the approved Apple TV screen source, runs the actual check app, and writes a single summary. It does not ask anyone to watch the television. Build the isolated candidate after changing application code:

```sh
./build.sh --playback-checks
```

Keep a private capture configuration outside Git, for example under `.build/playback-checks/`:

```json
{
  "version": 1,
  "deviceID": "EXACT_AIRPLAY_RECEIVER_ID",
  "captureSource": {
    "uniqueID": "EXACT_APPROVED_SCREEN_SOURCE_ID",
    "name": "EXACT_APPROVED_SCREEN_SOURCE_NAME",
    "approvedAppleTV": false
  },
  "hdrFixture": "/absolute/path/to/short-direct-hdr.mp4",
  "fixtureEncoder": "/absolute/path/to/encoding-capable-ffmpeg",
  "cases": ["directHDR", "hlsSubtitles", "hlsNoSubtitles"]
}
```

The AirPlay ID and capture-source ID are separate identifiers. The example deliberately has no usable identifiers and refuses capture until the operator has identified and approved the exact Apple TV screen source and set `approvedAppleTV` to `true`. Discovery alone is not capture approval. Never substitute a camera, microphone, first discovered device or default input. Source identification is a one-time supervised setup, not an automatic choice made by the batch.

The HDR fixture must already be a short, original-format HDR clip, 45 to 180 seconds and at most 2 GiB, with compatible audio and audible content near the start and 15-second position. The workflow reads it without altering or encoding it. For the two HLS cases it generates a 60-second moving test pattern and tone, then checks the actual encoded tracks and audio levels with the candidate's bundled engine. This requires an explicitly selected development FFmpeg with `libx264`; nothing is downloaded or substituted into the app. Test fixture generation is separate from AirCiller's original-format playback policy.

After the one-time source and credential approval, with the TV reserved for tests:

```sh
python3 Scripts/playback_checks.py /absolute/path/to/capture-config.json --capture --run --tv-is-idle
```

Without `--run`, this command only validates the configuration and local file bounds; it opens no process or device. Add `--prepare` to probe the HDR input and generate and validate the synthetic fixture without discovery, Keychain access or television playback. `cases` selects from the basic cases and optional scenarios below. An unavailable credential or capture source stops a live batch before any clip starts; it does not trigger pairing or fall back to an unwatched control-only pass.

Each case has its own capture gate. Authorization finishes first, then the verified screen source supplies its first video frame, and only then does playback start. Capture uses one muxed Apple TV input with video and audio sample outputs. The exact source ID, name, model, transport and media types are checked before input creation and monitored during capture. No camera or microphone is opened, and there is no preview or movie-file writer.

Ordinary capture cases are bounded to 120 seconds, 240 reduced frames, 1,024 measurements and a 128 MiB frame budget. The explicit long-pause cases allow at most 480 seconds but retain the same frame, measurement and byte limits. A separate watchdog also bounds stalled capture calls. Audio is measured in memory; raw audio is not saved. Process groups belong to the invocation, and disconnects, missing readiness, timeouts, interruptions or process leftovers cannot pass. Captures stop when their case finishes; the workflow starts no permanent service.

The final `report.json` is in a new private `.build/playback-checks/capture-run-.../` directory. It records candidate, capture-tool and fixture hashes, separate control and sampled-output verdicts, counts and evidence gaps. Detailed control reports remain unchanged. Local frame images, subtitle fixtures and plans stay in that ignored directory and must not be uploaded. Reports contain no source identifiers, movie names or raw OCR text. Failed runs remain available for diagnosis; the workflow never overwrites an earlier report. There is no automatic retention policy yet, so remove old private run directories when they are no longer needed.

`sampled_output_observed` requires passing receiver checks and cleanup plus moving picture, non-silent audio and the expected subtitle presence in the aligned playback window. Subtitle cues include a fresh per-case identifier; the HLS image must match the generated color pattern. An advancing timer, a screensaver, stale subtitle text, truncated coverage, silence or missing capture evidence cannot establish that result. All other cases stop the batch with a named gap or blocked result.

These are sampled digital-output checks. They do not certify physical speakers, Atmos channel layout, television HDR rendering, frame-accurate subtitle timing, physical remote use or whole-movie reliability. The control-only mode below retains its deliberately different `automated_checks_passed_output_unverified` result.

## Optional scenarios

Keep the same command and select the desired names in the capture configuration's `cases` array. The default remains the three basic cases. A configuration accepts up to ten distinct cases:

| Case | Actions and required evidence |
| --- | --- |
| `directTrackChanges` | Replace one external text subtitle with another during direct HDR playback. Require a fresh cue identifier and the receiver's resumed position. |
| `hlsTrackChanges` | Replace the subtitle, change original audio tracks, then disable subtitles. Observe each phase separately and require the corresponding cue and audio tone. |
| `cancelPreparation` | Observe AirCiller's actual preparation FFmpeg process running, press Stop through the coordinator, verify cleanup and watch for delayed playback. No audiovisual capture is started for this case. |
| `playlistTransition` | Open two items through the normal Playlist action. Observe the first, seek into its final six seconds, wait for the receiver's natural-end event, and require exactly one automatic load of the second item. |
| `directLongPause`, `hlsLongPause` | Observe the clip, obtain a receiver-confirmed pause, seek to second 15 while paused, retain the same session for six minutes, then require the receiver to resume at that target without loading again. Require separate captured picture, audio and subtitle evidence after resuming. |
| `hlsHDRNoSubtitles` | Exercise HDR through multiplexed HLS without subtitles. Require the generated HDR color pattern, motion, digital audio and receiver controls. See [transport-stream validation](TRANSPORT_STREAMS.md) for the bounded fixture override. |

The long-pause supervisor suspends frame and audio-measurement persistence during the hold. The explicitly approved Apple TV input stays active and its identity remains guarded. Persistence resumes before the post-pause observation window. This bounds stored evidence without relaxing camera exclusions or inventing output samples for the paused interval. The commands originate in AirCiller, so this does not validate a physical remote or prove how the receiver behaves without a capture connection.

The first device attempt stopped before the hold because its test required a position in the paused notification. This receiver supplied the pause state without a position. The test now uses a paused seek to a fixed target: the command acknowledgement alone is insufficient, and a fresh receiver position after the full hold must match second 15. Missing pause state, missing seek acknowledgement, an incorrect resumed position or an early resume cannot pass. The original unsuccessful report is retained; it was not evidence of a broken playback session.

A second attempt completed the six-minute direct HDR hold and resumed at second 15, but its evaluator rejected a brief loading notification between Resume and confirmed playback. The evaluator now permits that bounded transition while still rejecting loading during the hold or either stable output window. Regression cases cover both accepted and rejected intervals. Reassessment uses the original control, sample and frame-analysis files without modifying them; its separate report identifies the evaluator and input hashes. It is not presented as a fresh device run or as an originally passing batch.

For example, use `"cases": ["directTrackChanges", "hlsTrackChanges", "cancelPreparation", "playlistTransition"]` for the new scenarios, or include the three basic names for the complete current batch. New scenarios do not substitute for basic startup, pause and seek checks.

The HLS track-change fixture has two original E-AC-3 stereo tracks with different tones, 880 Hz and 440 Hz. Only the generated fixture gains an extra audio track; private movie tracks are not encoded or modified. The sampler measures the known tone frequencies in memory and saves numbers, not raw audio. The check requires the expected tone after the track change, so merely selecting a row cannot pass it. This is a fixture-specific signal check, not a test of surround layout or sound quality.

Each stable playback phase has a bounded observation window and must have its own fresh receiver-start evidence. Windows are assessed independently: an earlier subtitle, moving picture or audio sample cannot pass a later phase. Applying track settings uses the normal coordinator action and preserves original-audio mode. Both text tracks must have distinct fresh identifiers. The Playlist scenario uses the normal two-file open action and records load order without including file paths in the report; it never invokes the completion callback or starts the second item manually.

Cancellation is a negative test. If preparation finishes before the running process is observed, the case stays unverified. Its successful result is `preparation_cancellation_observed`, with `outputVerification: not_started`, not an audiovisual pass. A successful batch containing this case uses `selected_checks_passed`; each captured case retains its own `sampled_output_observed` result. Missing receiver positions, unexpected playback, repeat Playlist loads or leftover processes cannot pass.

The tail-seek scenario checks end-of-item behavior, not uninterrupted playback of the complete clip. Stopping a live media-preparation process does not establish cancellation of every analysis or OCR operation. Those boundaries, and long pauses, remain separate coverage.

## Build and validate inputs

Use the pinned dependencies already required by the project:

```sh
./build.sh --playback-checks
python3 Scripts/playback_checks.py /absolute/path/to/local-plan.json
```

The second command only validates the JSON and local file bounds. It does not decode media, initialize the coordinator, scan the network, read Keychain or contact a receiver. Ordinary `./build.sh` and `./Scripts/check.sh` never launch playback checks.

Keep the plan and clips outside tracked files, for example in `.build/playback-checks/`. A plan has this form:

```json
{
  "version": 1,
  "deviceID": "EXACT_ID_FROM_THE_CHOSEN_RECEIVER",
  "clips": [
    {"path": "/absolute/path/to/direct-hdr.mp4", "route": "directHDR", "subtitleIndex": 2},
    {"path": "/absolute/path/to/sdr.mkv", "route": "hls", "externalSubtitle": "/absolute/path/to/cues.srt"},
    {"path": "/absolute/path/to/sdr.mkv", "route": "hls"}
  ]
}
```

Plans accept up to six local clips, each no larger than 2 GiB and between 45 and 180 seconds once probed. Check for audible content in both the opening seconds and the post-seek interval around 15 seconds; an audio track alone does not establish an audible fixture. Use numbered subtitle cues from the start and a declared language, for example a filename ending in `.eng.srt`. An unknown-language track does not establish automatic receiver selection. Preserve original movies and encoded tracks when extracting clips. Synthetic SDR fixtures are useful, but must not be presented as validation of Dolby Vision, Atmos, high bitrates or a full movie.

The HDR case must contain real HDR and a selectable subtitle to exercise AirCiller's direct MP4 path. The HLS case must be SDR. A subtitle index is the absolute stream index returned by ffprobe, not its row number. The basic control runner accepts embedded PGS/VobSub through the app's normal OCR preparation; external subtitles remain limited to text and 4 MiB. The reusable capture configuration generates text cues, so a bitmap-output check needs its own private plan and comparison with source bitmaps. An audio track that requires conversion blocks the case. Omitting subtitle options explicitly tests without subtitles.

## Run against a free Apple TV

Close other AirCiller copies and confirm nobody is using the chosen TV. Then run:

```sh
python3 Scripts/playback_checks.py /absolute/path/to/local-plan.json --run --tv-is-idle
```

`--tv-is-idle` is the operator's confirmation of a reserved test window. The runner refuses to start alongside another AirCiller process, but cannot currently determine whether another app is playing on the television. Do not use that flag without checking. It targets only the exact receiver ID in the local plan, never the first discovered device.

The check app uses a separate preferences domain, disables automatic updates and startup cache pruning, and clears only its own preferences. The daily Playlist, history, language settings and app bundle are untouched. Keychain reads use the established AirPlay store. All Keychain writes and new pairing are disabled in this build.

Local certificate-signed builds use a [stable, read-only credential service](CREDENTIAL_SERVICE.md), copied unchanged between app builds. A certificate alone did not resolve the Keychain's per-build partition check. Explicitly authorize the component's access to the existing AirPlay credential before its first batch:

```sh
".build/AirCiller Playback Checks.app/Contents/MacOS/AirCiller" --authorize-keychain EXACT_RECEIVER_ID
```

That command allows one Keychain read and macOS's approval dialog, which can identify the component as AirCiller Keychain. Choosing Always Allow grants subsequent access to this signed component. Replacing the component or signing identity may require another approval. The command does not scan, pair, play, modify credentials or print their contents. `--check-keychain EXACT_RECEIVER_ID` performs the same read without allowing a dialog. Neither command needs a free television.

Earlier verification on 5 September 2026, before the service: the unapproved candidate refused access without a dialog in under one second. After explicit approval, two separate invocations succeeded without interaction. A rebuilt candidate with changed executable contents and the same certificate and application identifier refused access again. Both signed candidates passed signature verification outside the tool sandbox, and the full strict check suite passed. This failure motivated the separate component.

Service verification on 6 September 2026: the unapproved service refused a noninteractive read. After one explicit approval, the actual check app read the real AirPlay credential without interaction. A second copy, repackaged with changed signed metadata, had a different code-directory hash and the byte-identical service. Two invocations of that copy also read the credential without another dialog. This is a changed app-signature test, not a second Swift source compilation. Synthetic tests separately checked rejection of wrong identifiers, wrong signers, unhardened clients, debugger and loader-environment exceptions, and a modified service. The full strict check suite and separate check-app build passed. No movie or capture was started, and the installed app was unchanged.

Automatic batches disable Keychain interaction for their own process before creating the coordinator and request noninteractive reads from the service. Missing approval or a locked Keychain ends the run as blocked; the batch cannot open repeated password dialogs. This does not weaken the Keychain's access controls or change the installed app's interaction policy. The service and a small test-only C bridge use the file-based Keychain's process-local API because this existing store is not the data-protection Keychain handled by `LAContext`.

Each step has a deadline. The launcher also imposes a 30-minute ceiling for the complete batch and terminates only its own process group after interruption or unexpected leftovers. Closing the check window cancels the run. Keep the launcher running until cleanup finishes.

For a separately authorized capture, the plan can include an absolute `captureReadyFile` path ending in `.ready`. Use a new path for every run; an existing marker is rejected. The runner completes discovery and authorization first, prints `awaiting_capture_ready`, then waits up to two minutes. Only after the exact Apple TV capture reports that recording has started should its controller create that marker. No clip starts beforehand. The marker coordinates timing only; it cannot pass audiovisual checks or authorize opening a camera.

## Read the result

The launcher prints the path to a local `report.json` under `.build/playback-checks/run-…/`. The directory is private to the current user. Reports contain the candidate executable's SHA-256, clip numbers, requested playback routes, completed steps, elapsed time, sanitized helper events and cleanup results. They omit movie names, file paths, receiver IDs, network addresses, credential fields and raw error messages. Do not publish local plans or private fixtures.

- `automated_checks_passed_output_unverified`: the selected automatic cases passed. It is **not** audiovisual approval or authorization to publish.
- `inconclusive`: a deadline expired or some position checks lack receiver evidence. Inspect `completedSteps`, `unverifiedChecks` and any failed step before diagnosing a playback defect. Successfully checked controls remain recorded, even when exact playback progress needs a visual check.
- `blocked`: the device, authorization or fixture was unsuitable.
- `failed` or `incomplete`: a check failed, the app exited unexpectedly, cleanup could not be established, or the run was interrupted.

Only events originating at the receiver can establish progress and playback state. Command acknowledgements and AirCiller's interpolated timer cannot pass those checks. Confirming the seek destination requires distinct command IDs followed by a fresh receiver position at the expected destination. If the receiver omits that position, command acceptance can pass while the destination remains unverified.

Picture, audible sound/channel layout, subtitle appearance and physical-remote behavior are outside the current runner's observations. The report sets `outputVerification` to `not_observed` and lists the gaps. It does not ask the maintainer to watch each batch or convert an unanswered question into a pass.

Use the capture workflow above when sampled digital-output evidence is required. Receiver status alone cannot replace that evidence. A captured stereo signal or SDR image still cannot certify the television's physical speakers, Atmos layout or HDR rendering. Short clips also do not replace large-file, peak-bitrate or long-pause tests when those risks are affected.

Capture must never activate a Mac or iPhone camera or microphone, even as a preview. QuickTime's New Movie Recording workflow is unsuitable because it can start a default camera before a screen source is selected. Any capture helper must identify the exact Apple TV screen/audio source before opening it, reject camera inputs and stop on disconnect. Fallback to a default device is forbidden. Discovery and capture are distinct operations, and explicit discovery approval does not certify audiovisual output.

After explicit approval for wireless-screen discovery, a local experiment identified the receiver through CoreMediaIO and matched its persistent identifier in AVFoundation. Before opening its sole input, it required the exact identifier and name, external device type, `iOS Device` model, muxed media, non-Continuity identity and the expected transport. It has no default-input selection or preview. A bounded recording produced the Apple TV screensaver at 1920 × 1080 SDR with an AAC stereo track; a decoded frame was inspected. This establishes screen capture, not audible playback, HDR fidelity or subtitles. These temporary experimental files remain outside Git.

A follow-up capture completed while the playback runner was still waiting for macOS security authorization. The clips subsequently completed their control checks, but were outside that capture window. The security window could not be inspected by automation and was not accessed through another mechanism.

The runner supports `captureReadyFile` so authorization finishes before a bounded capture starts. The first experimental capture helper signalled readiness from its recording-start callback; the runner then released the clips. Local plan checks, the full strict validation suite and the separate check-app build passed for this change. The 5 September staged run was stopped while waiting for macOS authorization. Subsequent results are recorded below; those earlier reports have not been rewritten.

## Development validation, 5 September 2026

An isolated candidate ran three clips on the physical receiver: direct Dolby Vision with a text subtitle, HLS with a text subtitle, and HLS without subtitles. All three returned playing, paused and resumed states, acknowledged the rapid seek sequence and reported the final 15-second destination. Media requests and cleanup passed. The installed application and daily preferences were unchanged.

That run initially marked progress unverified because it evaluated progress before the first resume. Its recorded events contain the missing positions on resume. A subsequent regression covers that event sequence, and the runner now evaluates at the correct point. The original report is retained without rewriting its verdict. No person or capture system observed picture, sound or subtitle output during this batch; it is not audiovisual acceptance.

## Development validation, 6 September 2026

The stable credential service allowed the full three-clip batch after rebuilding the Swift check app, without another password dialog. The service executable stayed unchanged. Direct Dolby Vision and both HLS cases passed receiver progress, explicit pause/resume, rapid seeks and cleanup in the run without capture.

The first coordinated recording exposed two separate problems. `AVCaptureMovieFileOutput` ended HLS recording early with AVFoundation error -11813, and the receiver reported an immediate pause around that boundary. The runner then toggled the already-paused receiver to playing while waiting for a pause. Explicit commands fix that test error; regression tests cover both initial states and failed command delivery. The initial mismatch reports remain failures, not playback acceptance. The complete strict local suite and rebuilt check app passed after the correction.

A second, local-only prototype reads `AVCaptureVideoDataOutput` and `AVCaptureAudioDataOutput` from the same verified, single Apple TV input. It does not use a movie writer, preview, camera, microphone or default-input selection. The first received video sample releases the playback gate. It saves at most 90 reduced frames and bounded PCM level measurements during a 35-second window, using host receipt times so source timestamp changes do not define the recording length. Local Vision OCR and central-frame differences are evaluated separately from receiver control evidence.

The original HLS fixture had near-silence in the portions exercised by the runner, so it could not validate audio presence. A 60-second synthetic moving pattern with an 880 Hz tone was prepared as H.264 and E-AC-3 stereo. Fixture generation used the already installed, encoding-capable FFmpeg 9.0.1; playback still used only AirCiller's pinned bundled engine. No original movie was modified or encoded. The subtitle fixture now declares English in its filename and contains numbered cues from the first frame; the earlier unknown-language fixture did not establish visible subtitles on direct MP4.

Separate sample captures established moving picture and non-silent audio in all three cases. Numbered cues were visible when requested and absent from the sampled no-subtitle case. The same rebuilt candidate passed receiver progress, pause/resume, rapid seeks and cleanup during each capture. No password dialog was needed.

| Case | Frames inside the playback window | Frames with a recognized cue | Audio samples above -60 dBFS |
| --- | --- | --- | --- |
| Direct Dolby Vision with subtitles | 17 | 17 | 29 of 45 |
| Synthetic HLS with subtitles | 19 | 17 | 41 of 46 |
| Synthetic HLS without subtitles | 18 | 0 | 40 of 47 |

Central-image changes were measured in all three cases, and representative frames were inspected. Pauses, seeking and startup make silent audio samples or temporarily absent cues expected; these counts are observations, not whole-stream quality percentages. Samples use approximate host-time windows with boundary margins and do not establish frame-accurate subtitle synchronization.

At that point the prototype and private sample artifacts remained under ignored `.build/playback-checks`. The reusable implementation now lives in `Tests/PlaybackCapture` and `Scripts/playback_capture.py`; private media, source identifiers and historical artifacts have not been copied into repository source. Reports still distinguish sampled digital output from physical speaker, Atmos, HDR fidelity and full-movie validation. The installed application was unchanged, all test and capture processes finished, and no Mac or iPhone camera or microphone was opened.

## Reusable-command validation, 6 September 2026

The full strict suite and isolated check-app build passed. The rebuilt candidate read the existing credential noninteractively, using the unchanged service. Configuration-only mode opened no processes. Fixture-only mode validated the original HDR clip and generated an audible synthetic HLS clip without contacting the receiver. The new frame analyzer also recognized the generated pattern in earlier saved television frames without opening a capture device.

Fourteen capture-workflow regressions cover orchestration, malformed evidence and the documented command leaving no bytecode in repository source. Pure Swift tests reject camera and mismatched source metadata.

After the operator confirmed the TV was free, one invocation completed all three cases with `sampled_output_observed` and no evidence gaps. The workflow prepared the fixtures, verified the approved screen source, synchronized each capture with the check app, and produced the combined report. No password or manual viewing confirmation was requested. Each case passed receiver progress, explicit pause/resume, rapid seek acknowledgements and destination, media requests and cleanup.

| Case | Frames inside the playback window | Frames with the fresh subtitle identifier | Audio measurements above -60 dBFS |
| --- | --- | --- | --- |
| Direct Dolby Vision with subtitles | 16 | 16 | 32 of 48 |
| Synthetic HLS with subtitles | 17 | 17 | 41 of 46 |
| Synthetic HLS without subtitles | 18 | 0 | 37 of 46 |

Central-image changes were measured in all three cases. Both HLS captures included the expected test pattern. The no-subtitle case contained no recognized test cue in its playback window. Representative frames were also inspected from the saved images; no capture input was reopened for that inspection. The window alignment uses the runner and sampler's shared host uptime, not a manually estimated offset.

The final report and detailed evidence remain in the private local run directory. The check-app executable matched its pre-run hash, the stable credential service was unchanged, and no check-app, playback-helper, capture or analysis process remained. The installed app matched its original hash and was not replaced. No Mac or iPhone camera or microphone was opened. This confirms the integrated short-clip workflow; physical speaker output, Atmos layout, HDR rendering, full-movie playback and the remaining control profiles are still separate checks.

## Expanded-scenario validation, 6 September 2026

The optional scenarios were added after that successful basic batch. Fourteen existing capture-workflow tests and seven new scenario tests pass, alongside the extended Swift evidence and tone-identification tests. They cover fresh receiver evidence, per-phase timing, stale cues, unchanged or unmeasured audio tones, repeated Playlist loads, missing natural-end events, incomplete cancellation evidence and source-policy regressions. The complete strict suite and isolated check-app build passed before hardware use.

With a separately confirmed free TV, a single invocation completed all seven cases as `selected_checks_passed`. The three basic cases passed again, followed by both track-change cases, active-preparation cancellation and the automatic Playlist transition. The candidate and installed-app hashes remained unchanged throughout the run. No password or manual viewing confirmation was requested.

| Scenario | Observed result |
| --- | --- |
| Direct HDR subtitle change | Initial cue in 8 of 8 sampled frames; replacement cue in 7 of 7. Moving picture, audio presence and receiver-confirmed resumed position passed in both phases. |
| HLS subtitle change | Replacement cue in 7 of 7 frames. The original 880 Hz audio track remained present. |
| HLS audio change | The selected 440 Hz tone matched all 19 active audio measurements, with the subtitle still visible in 8 of 8 frames. |
| HLS subtitles disabled | No test cue in 7 sampled frames; the 440 Hz audio track remained present in all 19 measurements. |
| Preparation cancellation | The real FFmpeg preparation process was observed running, then Stop released the runtime and output directory. No playback event or media request appeared during the three-second follow-up. |
| Automatic next item | A receiver natural-end event followed the seek into the final six seconds. Load order was exactly `[1, 2]`, and the second HLS item supplied moving picture, no test subtitle and the expected 880 Hz tone. |

The sampler and application used a separate five-second observation window for each stable phase; the report applies boundary margins to those windows. Saved representative frames from the replacement-subtitle and subtitles-disabled phases were also inspected. The negative cancellation case opened no audiovisual capture input and is not described as a playback pass. All scenarios confirmed cleanup; no check-app, playback-helper, capture or analysis process remained after the batch. The stable credential service and installed app were unchanged. Private source identifiers, clips, subtitle cues and captured images remain outside Git.

This validates the bounded scenarios above. Long pauses, cancellation of primary analysis or bitmap OCR, physical remote use, physical HDR/Atmos presentation and uninterrupted whole-movie reliability remain separate coverage. No release, installation or dependency update was performed.

## Long-pause validation, 6 September 2026

Direct HDR and HLS completed separate six-minute holds with the same isolated candidate. Both runs kept one loaded item and its prepared directory, obtained a receiver position of 15 seconds on resuming, and cleaned up afterwards. Only the approved Apple TV input was used. No password or viewing confirmation was requested; the installed app and stable credential service remained byte-identical.

| Route | Hold | Captured evidence after Resume |
| --- | --- | --- |
| Direct HDR | 360.051 seconds | Moving picture in 5 of 6 sampled frames, fresh subtitle in 6 of 6, non-silent digital audio in 18 of 19 measurements. |
| HLS/fMP4 | 360.058 seconds | Moving picture in 7 of 7 sampled frames, fresh subtitle in 6 of 7, expected 880 Hz audio in 13 of 19 measurements. |

Direct HDR passed an offline reassessment of its unchanged evidence after correcting the loading-transition rule described above. Its original inconclusive report and the separate reassessment, including input and evaluator hashes, are retained locally. HLS passed a subsequent live invocation with the corrected evaluator. These are two separate results, not a claim that the original two-case invocation passed end to end. Representative post-resume frames from both routes were inspected too.

The final strict local suite passed with the corrected evaluator, including its negative-evidence regression cases. After testing, no check-app, capture, analysis or playback-helper process remained. This closes the bounded pause-and-resume cases with active Apple TV capture. It does not establish physical remote commands, uncaptured-session behavior, physical speakers or HDR/Atmos rendering, whole-movie playback, or the remaining full in-app bitmap cancellation scenarios. No release, installation or dependency update was performed.

## PGS canvas output validation, 6 September 2026

A focused HLS run used a 720p moving-pattern fixture with an embedded 1080p PGS track. The isolated app selected that bitmap track and used its normal OCR and HLS preparation. No external text subtitle was substituted. The control runner now accepts supported bitmap tracks; the application and capture implementation did not change during this follow-up.

The full strict suite and rebuilt isolated candidate passed before the run. Startup, receiver progress, pause, resume, rapid seeks to second 15 and cleanup passed in a 16.35-second case. The approved Apple TV source supplied 18 playback-window frames with measured motion, including 10 recognized pattern frames, and non-silent digital audio in 44 of 49 measurements. Credential access remained noninteractive.

The captured text was compared with decoded source bitmaps. Two distinct cues, one near the beginning and one after seeking, retained their words and brackets without clipping. This closes the focused canvas-presentation check. The capture supervisor's original report remains `captured_for_review`; a separate local assessment records the frame comparison. It is not the reusable synthetic-cue classifier's automatic subtitle verdict, and the maintainer did not have to watch the television.

The candidate, capture tools, fixture and evidence hashes remain with the private run. No test, playback or capture process remained afterwards. The installed app and credential-service executable were unchanged. Only the exact approved Apple TV input was opened, with no camera, microphone, preview or fallback. This is sampled HLS output, not a new direct-HDR run or certification of pixel-identical styling, frame-accurate synchronization, physical speakers, HDR presentation or a whole movie. No installation or publication was performed.

## Local regression checks

### In-app bitmap cancellation, 6 September 2026

The isolated app also has a `cancelBitmap` profile. It enters the ordinary coordinator's selected preparation route without discovery or receiver authorization, blocks AirPlay startup before credential access, and uses the ordinary Stop and file-loading actions. Task-scoped observations watch actual FFmpeg extraction, active Vision requests and recognized cues. They do not replace the decoder, OCR results or application tasks. Each operation has a separate temporary cache, so a warm cache cannot skip the work under test or change the user's OCR cache.

Use a private plan with `"deviceID": "local-only"`, `"profile": "cancelBitmap"` and two to six distinct short clips. Each clip specifies its absolute `path`, `route` (`hls` or `directHDR`) and bitmap `subtitleIndex`. Inputs must be 45 to 180 seconds, at most 2 GiB, and have original audio accepted by the existing route. The selected subtitle must probe as PGS or VobSub. Capture markers and TV authorization flags are rejected in this mode.

```sh
python3 Scripts/playback_checks.py /absolute/path/to/bitmap-plan.json --run --local-only
```

For every clip, the check stops a running extraction process, stops OCR after it has recognized text while other requests remain active, and changes to another file during OCR. It requires completion of the cancelled conversion and its requests, terminated children, removal of bitmap and prepared-media output, an empty test cache, and no delayed playback or stale error during a two-second follow-up. The launcher owns the process group and has a five-minute ceiling. Missing work observations cannot pass.

All twelve cases passed with four private two-minute fixtures: PGS and VobSub in both HLS and direct HDR preparation. Cancellation-to-cleanup observations ranged from 3 to 56 milliseconds on this Mac; these are measurements of this run, not performance guarantees. Every case reported cleanup, and no test or playback process remained afterwards. No television, camera, microphone or credential read was needed. The installed app and stable credential service were unchanged.

The PGS packets came from an existing local track. VobSub fixtures were encoded from those bitmaps with explicit subtitle-duration correction; video and audio were copied. They exercise the DVD subtitle decoder, but do not certify arbitrary DVD palettes, damaged discs or external IDX/SUB pairs. The first malformed generated VobSub fixture was rejected for its excessive duration, and that report remains unchanged.

This work also found a real canvas fallback bug: a 1080p PGS track paired with a 720p video was cropped to the video dimensions before OCR. The fallback now checks the selected subtitle stream's declared dimensions before the video stream. Both the failed conversion and subsequent recognized-cue checks are retained as local regression evidence. The test-only change from `forEach` to an equivalent loop after building the tested candidate addresses the repository's lint rule; it does not alter the recorded candidate's behavior.

This validates cancellation during extraction and active OCR through both app preparation routes. It does not test cancellation at every instruction of the final atomic cache write. The separate [PGS output run](#pgs-canvas-output-validation-6-september-2026) above subsequently verified the corrected canvas presentation on Apple TV. No version bump, installation or publication was performed.

### Cancellation checks, 6 September 2026

Two new checks exercise local work without a television or private movie. A private FIFO keeps the real bundled `ffprobe` running while the same analysis-task owner used by the coordinator receives Stop or a replacement task. Both paths must reap the child within three seconds. A generated text image exercises Apple Vision repeatedly; cancellation must finish within three seconds without delivering another result. A pre-cancelled recognition request must be rejected too.

The first Vision run exposed `VisionError.requestCancelled` escaping as a recognition error. The OCR boundary now normalizes errors from cancelled tasks to `CancellationError`. Probe pipe readers close on cancellation as well as success; bitmap conversion checks cancellation before accepting recognition results and writing its cache. All focused tests pass. The later in-app bitmap scenarios above extend this evidence to extraction and active OCR through the coordinator; the final atomic cache-write boundary is not separately interrupted.

`./Scripts/check.sh` runs evidence/plan tests, process-watchdog tests and strict type checking of the opt-in app before building the ordinary app. It also compiles both capture tools without opening a device. It does not need a receiver or private films. The regression cases cover duplicate and stale events, command-only replies, seek jumps masquerading as progress, invalid plans and numeric values, a child process that survives its parent, wrong source identities and camera metadata, missing capture readiness, premature capture exit, malformed evidence, stale subtitle cues, silence and incomplete coverage. Capture orchestration tests use fake processes; source-policy tests use plain values and never create a capture input.

No timing thresholds are used to claim playback performance gains. Step durations are diagnostic measurements of that particular run.

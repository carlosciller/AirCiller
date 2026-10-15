# HLS audio timing

## 0.17.0 scope, 15 October 2026

The repair has bounded local and Apple TV digital-output evidence. Publication
and installed-update verification are separate distribution stages.
Direct MP4 and HDR HLS packaging remain unchanged. Ordinary zero-adjustment
HLS retains its established packaging policy.

Adjusted SDR uses separate video/audio renditions on a shared clock, without
MP4 edit lists. Finalized HLS version 8 playlists describe real leading/trailing
intervals with GAP tags. A positive adjustment retains video from the beginning
and allows delayed audio to finish after the last image. A negative adjustment
holds the first encoded video frame while retaining all leading audio. This
changes that first packet's timestamps/duration, without encoding or duplicating
its picture. The stream duration includes these intervals.

Movie history and chapter locations use the original source clock. Receiver
commands and the active slider use the presentation clock. Starting from zero
includes the complete leading interval; restarting at a later movie point maps
that point onto the new presentation. Stop restores the source clock, and its
late acknowledgement no longer republishes the retired presentation time.
The final captured history/replay/track-change run passed; earlier failures
and offline reassessments are retained separately below.

### Final integration acceptance

The fresh `capture-run-erg42wx2/report.json` passed on 15 October with check-app
SHA-256 `dde6b4b8bdd3d29b2de54f5b10fc2a7d86672f635543fd4cd0776121da7f3527`.
Its five observation windows each passed motion, digital audio and subtitle
checks with 10 to 12 assessed frames. It recorded 39 matching tone measurements
and 51 matching cue measurements, with no contradictions. Stop, saved source
position, replay, -5 to +5 to -5 changes, natural end and cleanup passed their
receiver checks. The independent delayed-audio tail and +5-second opening
evidence remain in the corrected positive run and offline reassessment below.

Two QA defects were fixed before this fresh run: cue recognition now keeps
transport-time OCR lines separate, and tone measurement requires a coherent
sinusoid without knowing its expected frequency. Pure incorrect tones remain
contradictions; uncertain buffers provide no frequency evidence. Regressions
cover DC offset, gain changes, transients, mixtures, noise and incorrect tones.
The original inconclusive reports have not been relabeled or replaced.
Capture-tool hashes are retained in the final report; thresholds and required
matching observations were not reduced.

The production-input fingerprint (sorted per-file SHA-256 for Sources,
Resources and CredentialService, then SHA-256 of that manifest) is
`a525cbac45067d04c257804d0f43568159f64cc5fcf2e0f94c8827bd4ce5dee5`.
It is unchanged from the corrected native UI and three-path regression batch
`capture-run-3tmk7ug5`. The latter separately passed direct HDR with subtitles,
HLS with subtitles and HLS without them. Differences between those check-app
executables are QA observation windows, not production playback code. Release
version metadata does not alter these inputs; pinned engines are unchanged.

These observations establish sampled digital output and recorded receiver
controls. They do not certify physical speakers, HDR rendering, physical
remote use, frame-accurate synchronization or whole-movie reliability.

### Local conservation and cache

`Scripts/validate_hls_audio_timing_service.py` drives the actual preparation
service against bounded synthetic MKV and a TS derivative with a nonzero origin.
Forty cases passed: Original at positive/negative 0.05, 0.5 and 5 seconds, cold
and warm; explicit E-AC-3/stereo-AAC output at positive/negative 0.5 and 5 seconds.

Each Original case retained all 1,440 video packets and 1,875 encoded audio
packets. Coded-picture hashes and every encoded audio payload matched the source.
Packet timing checks cover the explicit first-frame hold and the remaining
common-clock shift, with a one-millisecond source-clock tolerance. Renditions
cover the complete presentation. Warm cases hit the cache; timeline metadata
is hashed, bounded and copied independently into each session. Corrupt metadata
and remote gap references are rejected by deterministic regressions.

Explicit audio conversions retained coded video and complete audio duration;
they are not sample-identical audio claims. PCM-to-FLAC manual adjustment remains
unavailable under its existing eligibility rule. The new range guard rejects
nonfinite or out-of-range audio adjustments before launching preparation.

Private local reports: `.build/audio-timing-service-matrix-20261015-3/report.json`
and `.build/audio-timing-service-ts-matrix-20261015/report.json`. Earlier failed
matrix attempts are retained. One assertion initially rejected floating-point
roundoff at the exact one-millisecond boundary; its tolerance now includes
1e-9 seconds for arithmetic roundoff. A later cache miss exposed unsupported GAP
metadata admission and led to the cache regression above.

### Earlier receiver evidence, before expanded integration

The isolated check executable was
`33138cc2f08274df3ef7d6c327e08e09c306b090bae9c4a58cafd8e1b3a041e9`.
The pinned engines were unchanged. Only the previously approved exact Apple TV
digital screen/audio source was used; no camera or microphone was opened.

- **+5 seconds:** receiver controls, pause/seek/resume, complete natural end,
  moving picture, cue presence, initial silence and the delayed audio tail were
  observed. The raw report is inconclusive because the first evaluator used the
  frozen last image as a clock for subsequent audio. All eight contradictory
  comparisons occurred outside the recorded moving-video windows. A separate
  offline reassessment restricts clock comparisons to those windows and retains
  independent tail checks: 28 matching tones, zero mismatches, 16 initial silent
  measurements, no premature audio. A further offline cue-clock assessment
  finds 11 matching subtitle intervals with no contradictory cue. The original
  report is unchanged.
- **-5 seconds:** a fresh run passed receiver controls, complete opening,
  pause/seek/resume, natural end, motion, cue presence and 31 matching tone
  measurements with zero mismatches. Offline cue-clock assessment finds 12
  matching subtitle intervals with no contradictory cue. The first image is deliberately held;
  later movie content continues on its shifted clock.

Private reports: `.build/playback-checks/capture-run-jqzgkm_f/` and
`.build/playback-checks/capture-run-l4deitjb/`. These sampled observations do not
certify physical speakers or frame-accurate timing. Cue-clock reassessments use
the unchanged saved captures and preserve their new analyzer/evaluator hashes
under `offline-audio-timing-cue-clocks.json`; they are not new device runs.
These earlier captures do not establish latest-candidate history/track-change
or Stop/replay acceptance; the corrected runs are recorded below. The full
strict local suite passed after the history/cache changes. Publication and
installed updating have not run.

### Expanded integration and local-Stop regression

On 15 October, the negative profile was extended to check Stop, saved source time,
replay and changes between -5 and +5 seconds. The positive case passed first in
`capture-run-9hbyqqou`: 19 matching tone measurements, no contradictory tones,
15 matching subtitle intervals and complete receiver-confirmed tail playback.
The negative case failed immediately after Stop, before its replay phase.
Its report is retained; it is not an approved negative integration result.

The failure exposed a real ordering bug. The coordinator had already restored
source position and duration when the helper's local-Stop acknowledgement
arrived. The controller published its retired presentation clock again, which
could overwrite the restored state. Local Stop now acknowledges closure without
publishing that clock. A receiver-initiated Stop still publishes its final time
before invoking cleanup.

`AirPlayControllerStopSmokeTest` drives the real JSON decoder and event handler
without launching a helper. It fails against the previous behavior and passes
the correction for normal/silent local Stop, remote Stop, late events/ticks and
old-session isolation. The expanded hardware profile additionally records
immediate, settled and persisted values after Stop, without loosening its
position checks. The subsequent corrected run below establishes those control
checks separately from captured-output acceptance.

### Corrected candidate: positive adjustment and offline reassessment

The corrected executable is
`53439d94c965663c78812b3bc9357b2c8c0ab45162758067d46ecd50651009e1`.
Its +5-second run in `capture-run-racqvvrf/case-01/controls.json` passed
receiver controls, pause/seek/resume, natural end and cleanup. The original
`report.json` remains inconclusive with `insufficientCapturedFrames`; it has
not been replaced or converted into a passing batch.

The initial observation lasted 12.075 seconds, but the evaluator selected only
its last five seconds. After its existing half-second margin at each end, that
left five video samples. The saved capture contains eight samples in the last
seven seconds after applying the same margins. Those seven seconds start after
the deliberate five-second audio delay or opening-image hold, since the initial
window must last at least twelve seconds.

The evaluator now uses that seven-second interval for the initial audiovisual
check. It still requires six distinct frames spanning at least two seconds,
coverage within 1.5 seconds of each trimmed edge, motion, picture/cue recognition
and active audio. The independent complete-opening, silence, tone-offset,
subtitle-clock and delayed-tail checks are unchanged. Deterministic regressions
exercise the real shared evaluator at moderate picture cadence in both delay
directions: the earlier five-second selection fails, the seven-second selection
passes, and insufficient frame count or edge coverage still fails. All 88 local
Python playback tests passed after the evaluator change.

A separate offline assessment of the unchanged +5-second capture observes eight
initial frames and seven after pause, 25 matching tones with no mismatches,
18 initial silent measurements with no premature audio, and 11 matching cue
intervals with none contradictory. Its outcome is `sampled_output_observed`.
The private record is
`.build/playback-checks/capture-run-racqvvrf/case-01/timing-reassessment-seven-second-opening.json`.
It records the candidate and evaluator hashes and the hashes of the unchanged
original report, controls, frame analysis and sample manifest. This is an
offline reassessment, not a new capture or a physical speaker/timing claim.

### Corrected negative controls and remaining capture gap

The same corrected executable completed every negative-profile control check
in `capture-run-yzhxvx86`: Stop and cleanup, saved source history, replay,
-5 to +5 to -5 changes, pause/seek/resume and natural end. Source position after
Stop was 20.077359910 seconds immediately, after helper shutdown and in persisted
history; all three durations were 60 seconds. Each new presentation target was
independently confirmed by the receiver.

The output report remains inconclusive. Its final `timingAdvanceRestored`
window lasted 5.041 seconds and contained six captured frames; the final frame
fell inside the existing half-second end margin, leaving only five usable
frames. The other windows met the shared output check: initial 11 frames,
after-pause seven, replay seven, and the +5 change six. The private diagnostic
`capture-run-yzhxvx86/case-01/observation-window-diagnostic.json` retains the
recorded intervals, sample counts and exact failure. No window was extended
after capture, and no threshold was lowered to accept the run.

The negative check now records seven actual seconds after pause and after each
of its three transitions. The evaluator requires 7 to 9 seconds, preserving its
two-second scheduling allowance and every audiovisual acceptance threshold.
The positive profile and other scenarios retain their existing durations.
The initial opening and natural-tail checks are unchanged. Four additional
two-second observations add eight seconds to the measured 70.09-second run;
this remains within the unchanged 120-second capture and 165-second control
limits. A fresh negative capture is required to establish final sampled-output
acceptance.

Fresh shared-control baselines on the corrected executable passed in
`capture-run-3tmk7ug5`: direct HDR with subtitles, ordinary HLS with subtitles,
and ordinary HLS without subtitles. All three report `sampled_output_observed`
without gaps. These samples do not establish physical HDR rendering or speaker
layout. Publication, installed updating and final app-close checks have not
been established here.

### Seven-second negative run and observer defects

The fresh run `capture-run-9s8c7uav`, executable
`dde6b4b8bdd3d29b2de54f5b10fc2a7d86672f635543fd4cd0776121da7f3527`,
completed all controls and all five basic output windows. Each window had
10 to 12 assessed frames, motion, fresh subtitles and active digital audio.
Stop preserved source position 22.161939974 seconds immediately, after helper
shutdown and in history; the source duration remained 60 seconds. Only the
test profile's observation duration changed from the previous executable;
production sources and pinned engines were unchanged.

The overall report remains inconclusive. The cue-index parser concatenated
unrelated OCR lines: a subtitle ending in index 3 followed by the transport
time `00:27` became an invalid longer index. Digital frames visibly retain the
correct subtitle. The deterministic regression fails with the original parser;
the corrected parser accepts one complete, current-token cue line and rejects
ambiguous, stale or oversized indices. A separately saved offline reanalysis,
`case-01/timing-reassessment-cue-lines.json`, finds 11, 7 and 13 matching cue
intervals in the three transitions, with none contradictory. It preserves the
original files and records input and analyzer hashes.

Two tone estimates remain unresolved in that capture: 395.05 Hz where 440 Hz
was expected, and 931.78 Hz where 880 Hz was expected. There were 65 matching
measurements. Neither questionable estimate is the opposite fixture tone;
the retained measurements do not establish whether the transient came from
the receiver or the zero-crossing estimator. Raw audio is not retained, so
this report cannot be approved by recomputing those measurements. A focused
observer regression and fresh capture are required; no playback tolerance or
sample-count requirement is relaxed.

## Historical deferred investigation

Investigation, 13 September 2026. The maintainer chose to separate this repair from the startup optimization release after the receiver checks below failed. All experimental packaging, subtitle-timeline and cache-format changes were removed from the delivery. The original manual audio-adjustment limitation remains; ordinary playback at zero audio adjustment is the accepted scope.

The following sections describe the discarded candidates, not the current application. Their source patches, test and failed captures are retained privately under `.build/startup-phase2/deferred-audio-repair/` for a separate design review. No experimental repair was installed or published.

## Symptom and scope

In SDR HLS playback, applying an audio delay could prepare a new stream without changing the relative audio/video timing. The startup cache test exposed this: the cache correctly missed, but the shifted and unshifted prepared media had identical hashes. The same command builder from the pre-optimization baseline reproduced the defect without a cache.

Separate video and audio outputs each used FFmpeg's `-avoid_negative_ts make_zero`. Each output normalized its own start, removing the requested relative offset. The candidate uses one multiplexed audio/video rendition only for SDR with a nonzero audio adjustment. The encoded media is still copied in Original mode. Ordinary zero-delay SDR keeps its separate audio rendition.

This repair does not change the direct MP4 packager or the existing HDR HLS timing policy. It adds no codecs, engines or conversion fallback.

## One presentation timeline

- Delayed SDR preparation keeps the video and selected audio on a shared clock. For inputs with different stream origins, the second input synchronizes to the first before applying the requested audio delay.
- The first and last HLS fragment timestamps determine the outer playlist intervals. An audio advance can add a leading audio interval; an audio delay can leave audio after the last video frame. The advertised duration must include those intervals without dropping encoded packets.
- WebVTT retains each complete cue and maps its movie-relative time to the prepared video's actual origin. Segment membership uses the same presentation clock, including cues crossing a boundary.
- The cache format is versioned separately from earlier drafts. Corrected base playlists are finalized before admission. A checkout gets independent playlist files; shared media fragments must remain immutable.
- These extra timestamp reads are local and limited to the outer fragments. The ordinary zero-delay path does not gain a full-file scan or another preparation process.

## Evidence retained

The original failed receiver cache run, the failed first repair and its incomplete tail coverage remain recorded in the [startup optimization report](STARTUP_OPTIMIZATION.md#phase-2-receiver-checks-12-september-2026). They are not successful tests of this candidate.

The command-builder investigation found a second issue in a synthetic transport stream whose video/audio started at 12.500/12.495 seconds. FFmpeg normalized the selected video input 5 ms differently from the audio input. Synchronizing the second input removed that residual. The pinned-engine comparison covers MKV and that TS derivative at zero, ±0.5 and ±5 seconds, with encoded-packet identity, stream duration and zero-delay byte comparisons. Private evidence is retained under `.build/startup-phase2/muxed-clock-regression-xb8in9je/`. This establishes remux timing, not Apple TV output.

The real preparation service subsequently passed fourteen MKV/TS cases: zero, ±0.5, ±5 seconds and warm replays of both half-second adjustments. Every case retained all 1,440 video packets and 1,875 selected audio packets. Relative offsets matched within 1 ms; stream durations were unchanged. Zero-delay served files matched the previous implementation byte for byte; warm delayed packages matched their cold counterparts. Additional cases passed with subtitles disabled. A deliberately staged old-format cache entry was not reused.

The test checked each segment boundary, its advertised duration, target duration, WebVTT map and the cues that belong to that interval. Both ±5-second preparations include approximately 65 seconds of total presentation, preserving the extra leading or trailing interval instead of trimming the original minute. The TS source has a nonzero origin. `Tests/HLSAudioDelaySmokeTest.swift` records the reproducible opt-in test; final private results are `.build/startup-phase2/audio-delay-service-3/results.json`, SHA-256 `c08523d81e2f52ee972a5962dc0be2cfdb28667914c08022565b422efa0d9c03`. The final Codable/style revision produced the same report as the preceding run.

Focused strict Swift 6 tests also passed single-fragment and reordered-video-timestamp cases, malformed probe responses, missing tools, timeout and cancellation with child-process cleanup. No failed test was converted to a pass by loosening its timing assertion.

This new real-media matrix covers H.264 with original E-AC-3 in MKV and TS. It does not add acceptance evidence for converted audio, FLAC, mono layouts, other codecs or HDR. Those are untested combinations here, not newly declared incompatibilities.

The complete application gate passed on 13 September with the repair sources. Later changes to the checker and offline capture reporter still require the final gate. Two nine-phase cache runs completed their receiver/control, base-identity and cleanup checks. Both full captured-output reports remain inconclusive because some windows lack enough samples. An offline reassessment retains the original reports and establishes sampled output for each phase in at least one run; it does not turn either batch into a pass.

The natural-end check exposed a further defect. For a +5-second audio adjustment, the Apple TV acknowledged a duration of 64.995 seconds and resumed at 56 seconds. An incoming end notification arrived 4.095 seconds later, coinciding with the last video frame while delayed audio remained. AirCiller immediately tears down the session on that notification. The later silence therefore cannot distinguish receiver completion from audio cut off by our teardown. This acceptance check failed. The earlier run that requested a fractional seek remains separately recorded as a checker-target failure; the corrected run requested exactly 56 seconds without relaxing the position tolerance.

Review of the same capture then found a stronger signal: the source's 880 Hz tone was already measured beside a frame showing source time 0.375 seconds, despite the requested +5-second audio offset. The continuous tone was present in further measurements before source time 5 seconds. This contradicts the requested initial delay without relying on an end-of-playback interpretation. Inspection of the equivalent retained local package found the offset in an MP4 edit list, while both tracks' first fragment decode times were zero. Apple documents using fragment decode timestamps instead of edit lists for its HLS profile, and starting the presentation at the earliest video timestamp. [Apple's fMP4 authoring explanation](https://developer.apple.com/videos/play/wwdc2020/10011/).

A bounded local comparison subsequently found a muxer configuration that preserves the same PTS, DTS, duration and payload for every packet while expressing the offset directly in fragment decode timestamps. Only adjusted SDR output now selects `make_non_negative` in both the HLS and inner MOV muxers, with `frag_discont` and edit lists disabled. Ordinary SDR, direct MP4 and HDR options remain unchanged. Cache format v4 rejects both earlier v2 and v3 packages.

The real-service matrix passed again with this configuration: fourteen recorded cases and four additional subtitle-disabled preparations. Every nonzero case additionally compares each fragment with edit lists enabled and ignored; stream identities and all packet timestamps, durations and payload hashes must match exactly. These twelve recorded nonzero cases each cover 3,315 packets. Results are retained in `.build/startup-phase2/audio-delay-service-4/results.json`, SHA-256 `884ec9765ec4cd8c0455debd6980c2d03637bf4e015ec0cb98e030a224160aa6`. This stronger test would reject the earlier edit-list-only repair. It remains local evidence pending a new receiver run and final application gate.

The next receiver run rejected this configuration at startup. When asked to start at zero with +5 seconds of audio delay, the receiver reported position 4.995; a captured frame showed source time 5.000 seconds. The test stopped immediately and confirmed cleanup. The real timestamp offset therefore changed receiver behavior, but skipped the beginning of the video. This is not a successful audio-delay repair. Evidence is retained in `.build/startup-phase2/audio-delay-tail-run-wtujssr8/`, checker executable SHA-256 `42e2f20b7fd8fa508de60988031ab019533fbfd83fa516d627ae5edbb4e16aa2`. No negative-delay case ran in that batch.

The next design question is how to retain the initial video interval before the first delayed audio sample without encoding replacement audio or dropping video. An HLS gap or separate rendition is not yet a validated solution. The private helper hold was never run and is not part of this correction. The normal helper is unchanged. Positive/negative adjustment, seek and natural end are not accepted; this repair must not be published or installed yet. Captured digital output remains separate from frame-accurate physical synchronization and speaker-layout claims.

## Reproduce the deferred experiment

This command is historical: its test and packaging changes are in the retained experimental patch, not in the release tree. Restore them only in an isolated investigation checkout. A local pass does not establish receiver acceptance.

Use the bootstrapped, pinned engine and a synthetic 60-second H.264/E-AC-3 MKV with at least one compatible audio track. The test checks the duration before running. It creates its TS derivative and subtitle fixtures inside a new output directory, and refuses to reuse that directory. No receiver or credentials are involved.

```sh
mkdir -p .build/tests .build/module-cache
xcrun swiftc -swift-version 6 -strict-concurrency=complete -warn-concurrency \
  -warnings-as-errors -O -module-cache-path .build/module-cache \
  Sources/Localization.swift Sources/AirCillerError.swift \
  Sources/ProcessDataBuffer.swift Sources/CancellableProcess.swift Sources/BundledEngine.swift \
  Sources/MediaModels.swift Sources/MediaProbeService.swift Sources/ExternalVobSub.swift \
  Sources/VODBuildProcess.swift Sources/VODCommandBuilder.swift Sources/StreamDiagnostics.swift \
  Sources/SubtitleService.swift Sources/ASSSubtitleConverter.swift Sources/PGSSubtitleConverter.swift \
  Sources/SubtitleOCRService.swift Sources/SubtitleOCRTextNormalizer.swift Sources/AirCillerStorage.swift \
  Sources/HDRConfigurationInjector.swift Sources/PreparedMediaCache.swift Sources/PlaybackStartupTrace.swift \
  Sources/HLSPreparationService.swift Tests/HLSAudioDelaySmokeTest.swift \
  -o .build/tests/hls-audio-delay

.build/tests/hls-audio-delay /absolute/path/to/synthetic-60s.mkv \
  .build/dependencies/AirCillerEngine-ffmpeg-9.0.1-python-3.13.15/ffmpeg/bin/ffmpeg \
  .build/dependencies/AirCillerEngine-ffmpeg-9.0.1-python-3.13.15/ffmpeg/bin/ffprobe \
  .build/hls-audio-delay-new-run
```

Sources: [FFmpeg input synchronization](https://ffmpeg.org/ffmpeg.html#Main-options), [timestamp normalization](https://ffmpeg.org/ffmpeg-formats.html#Format-Options), and [HLS WebVTT mapping and cue coverage](https://www.rfc-editor.org/rfc/rfc8216.html#section-3.5).

## Separate-rendition experiment, 22 September 2026

The maintainer authorized a separate follow-up investigation. The maintenance
candidate and both production packagers remain unchanged. One local iteration
used the pinned engine and a synthetic 60-second H.264/E-AC-3 fixture, retaining
separate renditions on a shared positive clock without edit lists.

| Requested adjustment | First video PTS | First audio PTS | Last audiovisual end relative to video start |
| --- | --- | --- | --- |
| 0 s | 10.000 s | 9.995 s | 59.999 s |
| +5 s | 10.000 s | 14.995 s | 64.995 s |
| -5 s | 10.000 s | 4.995 s | 59.999 s |

All three packages preserve the 1,440 video and 1,875 audio packet payloads in
order. Relative timing changes exactly by the requested five seconds compared
with the control, retaining its original -5 ms audio origin. Reading each MP4
with edit lists enabled or ignored gives the same packet timestamps and hashes.
The first video frame and full local video duration remain present. The source
fixture and pinned engine hashes are unchanged.

This is not a viable receiver candidate yet. The generated video playlist
announces 59.904 seconds for 59.999 seconds of samples. The audio playlist
announces 60 seconds, while +5 seconds requires presentation through 64.995
seconds relative to video start. No durations were overwritten to hide the
discrepancy and no Apple TV run was attempted.

The next gate is correct initial/final rendition intervals and the subtitle
clock. The existing `alignRenditionPlaylists` normalization must not truncate a
legitimate delayed tail in an experimental adjusted package. Only after local
acceptance should +5 seconds be checked for a complete video opening, initial
silence, delayed tone and retained tail on the receiver. Stop at the first
contradiction; the previous skipped opening is still an unresolved receiver risk.
Negative adjustment also needs an explicit leading-audio presentation policy.

Private reproduction commands, fragment files, packet comparisons and the report
are retained under `.build/hls-audio-investigation-20260922/`. This experiment
does not claim an audible timing fix, completed subtitle/seek checks or a release.

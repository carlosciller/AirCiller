# HLS audio timing investigation (deferred)

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

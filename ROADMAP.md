# Roadmap

AirCiller should remain quick to open, straightforward to control and dependable through a whole movie. This is the order of work, not a release schedule.

The 0.12.1 stability release covers playback controls, authorization, track editing and malformed data. OpenSubtitles, keyboard Playlist reordering, local PGS/VobSub OCR, language preferences and bundled engines are already available.

[The review record](Docs/STABILITY_REVIEW.md) records the local checks, CI and completed physical Apple TV tests. Release and signing steps are documented in [Distribution](DISTRIBUTION.md); user-facing changes are in the [release notes](CHANGELOG.md).

## 0.12.6: library and reliability

Implemented for 0.12.6. [Library recovery](Docs/LIBRARY_RECOVERY.md) and [capture readiness](Docs/PLAYBACK_CHECKS.md#initial-capture-readiness) record scope and validation separately, including local coordinator checks and the successful integrated Apple TV batch.

- Preserve Recents and saved progress when a movie's external drive is disconnected. Explain that the file is unavailable and offer to locate it again instead of removing it automatically.
- Detect unavailable Apple TV capture before starting a playback batch, with a bounded diagnostic and a clear reason to stop. Do not weaken approved-source checks or substitute control acknowledgements for audiovisual evidence.
- Carry the release's user-facing changes, compatibility limits and validation links through the changelog, GitHub notes and next signed update. Follow the [release documentation checklist](Distribution/ReleaseNotes/TEMPLATE.md#editorial-check-before-publication).

## Available: automated playback checks

The local, on-demand test runner exercises the actual AirCiller app and physical Apple TV. It stays outside the everyday interface, with no extra Apple TV app or permanent service.

The [implementation](Docs/PLAYBACK_CHECKS.md) covers startup, receiver progress, pause/resume, rapid seeks and cleanup in a separate development build. On 6 September 2026, one command passed the three basic cases using the approved Apple TV screen source. A subsequent seven-case batch also passed direct HDR subtitle replacement, HLS subtitle and original-audio changes, stopping an active FFmpeg preparation, and exactly one automatic Playlist transition after a receiver natural-end event. Controls and per-phase sampled output have separate recorded evidence. No password or manual viewing confirmation was required.

The six-minute pause profiles passed for both routes with captured output after resuming at second 15. The [record](Docs/PLAYBACK_CHECKS.md#long-pause-validation-6-september-2026) separates the corrected direct HDR reassessment and subsequent live HLS run. Local tests also cancel a running bundled analysis process through its task owner and a real Vision recognition batch. Twelve [in-app bitmap cases](Docs/PLAYBACK_CHECKS.md#in-app-bitmap-cancellation-6-september-2026) now pass extraction cancellation, OCR cancellation and file replacement for PGS and VobSub through both preparation routes, without using a receiver.

The focused [PGS output check](Docs/PLAYBACK_CHECKS.md#pgs-canvas-output-validation-6-september-2026) also passed: a 1080p subtitle canvas carried with 720p video reached Apple TV without clipping the compared cues. Controls, sampled motion and digital audio passed; the agent compared captured text with source bitmaps. This closes the remaining canvas check without repeating the six-minute pauses. These bounded checks do not establish uninterrupted whole-movie reliability or every atomic cache-write boundary. Installation and publication remain separate actions.

Local signed candidates now reuse a [stable, read-only credential component](Docs/CREDENTIAL_SERVICE.md). Synthetic access and caller-rejection tests pass. After one explicit approval, real-credential reads passed across different app signatures and a subsequent Swift rebuild. The three playback-control cases also passed without another dialog. Batches refuse interactive Keychain access. Retain the Keychain and its access controls; changing the service or signing identity can still require approval.

1. Prepare a small, repeatable set of short clips covering direct HDR/Dolby Vision and HLS/fMP4 with and without subtitles. Include audible content and visible cues from the start. Keep private media outside Git and preserve originals.
2. Exercise the Swift application, bundled AirPlay helper and local server together. Check receiver-reported progress, pause/resume, rapid seeks, track changes, cancellation, natural completion and a single transition to the next Playlist item. Testing only the helper would miss app lifecycle failures.
3. Use timeouts and one result report, with local checks, receiver evidence and human observations recorded separately. A successful command or an advancing Mac timer is not proof of television playback. Restore test settings and Playlist order, and leave no helper or playback server running. Do not interrupt an existing viewing session or reset pairing automatically.
4. Establish authorized, local capture of the Apple TV output so routine batches do not require the maintainer to watch. Verify motion, audio presence and subtitle cues against known fixtures. Treat unavailable capture as an explicit evidence gap, not a manual confirmation request after every run. Captured output does not by itself certify the television's HDR rendering or physical speaker layout; record those limits separately.
5. Run checks according to the change: documentation needs no television, interface changes need interface checks, shared controls need both affected playback paths, and engine or format changes need their audiovisual cases. Keep long-pause and large-file stress checks for changes that can affect them; short clips do not replace those tests.

Ongoing acceptance: after any necessary capture setup, one command runs the selected cases and reports control and captured-output evidence without asking the maintainer to watch each batch. Missing evidence stays unverified. Apply the current [validation rules](TESTING.md) to each delivery.

## Format expansion: delivered scope and remaining work

Prioritize keeping both video and audio in their original encoded formats. Remuxing into a compatible streaming container is allowed; it must not silently become audio or video transcoding.

1. TS, MTS and M2TS containers carrying already-compatible H.264 or HEVC and original audio accepted by the receiver.
2. Original FLAC soundtracks: implemented in 0.12.4 for preserved channel layouts, with separate stereo and 5.1 Apple TV checks. See [FLAC validation](Docs/FLAC_AUDIO.md).

Each addition needs a representative sample, copy-only audio/video verification, the relevant automated and audiovisual checks, clear rejection messages and a separate release decision. Add support only after the AirPlay receiver accepts it; FFmpeg being able to read a format is not enough.

Part 1 is implemented in 0.12.3. The [validation record](Docs/TRANSPORT_STREAMS.md) covers eight copy-only preparation checks, four Apple TV output cases and two subsequent embedded-PGS cases after fixing timing, canvas lookup and missing-language metadata. HDR without subtitles is assessed separately.

Follow up on FLAC channel-mask overrides that fMP4 does not currently preserve. Keep those cases behind explicit conversion approval until their original layout can be retained and verified. Do not reinterpret surround channels to make a test pass.

The first capture attempt supplied no initial frame until a separate known-good playback diagnostic restored capture output. The later format batch passed unchanged. Investigate this inactive-receiver startup condition separately; do not weaken source verification or treat a ready session as proof of visible output.

## Subtitles: delivered scope and remaining work

- External PGS `.sup` and VobSub `.idx`/`.sub` are complete for 0.12.5. [PGS](Docs/EXTERNAL_PGS.md) and [VobSub](Docs/EXTERNAL_VOBSUB.md) have separate local and captured Apple TV evidence. The VobSub record distinguishes automatic results from the visual review that confirmed a subtitle missed by the classifier. A brief HLS visibility gap immediately after seeking remains.
- Additional text subtitle formats. Check timing and styling individually; evaluate TTML/IMSC1 separately.

OCR and conversion to selectable text are separate from original audio/video passthrough. Never burn subtitles into the picture, upload them for recognition or modify the source files.

## Later

- An App Intent or Shortcut to send a file to Apple TV.
- Reliable title and artwork on the iPhone Lock Screen. Working remote control takes priority.
- DVB and XSUB subtitle OCR with suitable samples.

AV1 passthrough remains research only. A device decoder does not establish support in its AirPlay video receiver.

## Next dedicated update: faster playback startup

Planned after 0.12.6. This is a separate, measured engineering phase; implementation has not started. Notify the maintainer before beginning and wait for their readiness confirmation, as required by `AGENTS.md`.

The goal is to reduce the time from pressing Play to the first visible picture and audible content on Apple TV, while preserving original quality, selectable subtitles and reliable playback through the movie. Set numeric targets after measuring a baseline; do not promise a speed ranking without comparable evidence.

### Establish the baseline

- Measure the complete path with correlated, monotonic timings: file access, analysis, subtitle extraction and recognition, packaging, AirPlay connection, receiver loading and captured picture/audio. Record overlapping work so stage totals are not mistaken for elapsed time. Keep capture setup overhead separate.
- Compare repeated cold and warm runs, with explicit cache and connection states, on the same media, Mac, receiver and network. Cover direct HDR/Dolby Vision and HLS separately, small and large files, text subtitles, PGS/VobSub, no subtitles, and local versus slower external storage.
- Report individual runs, median and tail latency, preparation CPU/memory, temporary disk use and early buffering. First audio needs a known audible cue; a naturally silent movie opening is not a startup failure. A successful Play reply or moving Mac timer is not the endpoint.

### Investigate and deliver in measured steps

- Remove repeated probing, unnecessary process launches, redundant reads and waits on the critical path.
- Evaluate bounded parallel work, preparation-cache reuse and invalidation, subtitle extraction/OCR scheduling and cancellation, disk I/O, HTTP delivery, receiver buffering and connection reuse. Avoid speculative background work and persistent services.
- Profile the bundled FFmpeg and AirPlay components. Consider engine changes or upgrades only where measurements show a benefit, with reproducible builds and compatible behavior. A newer dependency is not an optimization by itself.
- Consider larger preparation or streaming changes in a separate design review if they require changing the complete-VOD or packaging invariants. Preserve full duration, seeking, HDR/Dolby Vision, original audio and selectable subtitles; no silent conversion or quality reduction to shorten startup.

Acceptance: reproduce before/after results against a pinned baseline and disclose both improvements and regressions. Validate each affected route and startup buffering, then the relevant seek, pause, cancellation and completion cases. Change one packager per delivery. Publish a readable performance report with the release notes; do not substitute synthetic microbenchmarks for end-to-end Apple TV measurements.

## Distribution

Playback engines stay pinned and bundled with the app. Dependency updates require a regenerated lock, import and packaging checks, and applicable hardware tests. Proposals that only change `requirements.in` are incomplete.

Builds now report component sizes and enforce a 165 MB logical-file budget. Review unused Python development and GUI components before considering a smaller runtime, with measured savings and complete runtime checks. No trimming has been applied to the tested engine.

Developer ID and notarization are blocked until an Apple Developer Program membership is available. Sparkle signatures do not replace notarization.

## Boundaries

No analytics, cloud library, permanent server, background indexing or silent conversion. Do not upload movies or bitmap subtitles for recognition. Preserve original files and keep direct MP4 and HLS/fMP4 packaging changes in separate deliveries.

Completed work belongs in the [changelog](CHANGELOG.md); validation belongs in [TESTING.md](TESTING.md).

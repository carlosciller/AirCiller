# Testing strategy

AirCiller separates three levels of validation so that a successful build is never mistaken for successful playback.

## 1. Deterministic checks

`./Scripts/check.sh` validates formatting, compiles the code in strict Swift 6 mode, runs tests without private media, and checks the Python bridge through a simulation.

## 2. Local tests with media

Executables in `Tests/` that require a real file receive its path through an argument or environment variable. Media remains outside the repository. These tests validate containers, OCR, AVPlayer, and VOD playlists, but they do not prove that tvOS will accept the session.

## 3. Physical Apple TV matrix

A version is not considered ready to install until these cases have been completed separately:

| Path | Minimum case | Expected result |
| --- | --- | --- |
| Direct MP4 | HDR/Dolby Vision, E-AC-3/Atmos, with selectable subtitles | Correct picture and tracks; synchronized duration and position |
| HLS/fMP4 | Without subtitles | Complete VOD, no live indicator or preparation pauses |
| HLS/fMP4 | With WebVTT | Selectable, synchronized subtitles that are not burned into the picture |
| Control | Long pause and resume from the remote | AirPlay remains linked and the Mac does not sleep automatically |
| Control | Natural end of the current item | The Apple TV confirms completion and the next Playlist item starts once |
| Control | Rapid pause, resume and seek commands from Mac, Apple TV Remote and iPhone Remote | Commands remain ordered, the timeline stays synchronized and AirPlay remains linked |

After playback, also test stop, replay, and closing the app. Only then should the patch version be increased and the installed app replaced, while keeping a rollback copy.

## 4. Signed application updates

The first complete Sparkle update was validated on 26 August 2026. The installed app moved from AirCiller 0.10.2 (build 42) to 0.10.3 (build 43) through the public signed appcast, installed the update, and relaunched successfully. The resulting app bundle and every embedded Sparkle helper passed strict code-signature verification.

Version 0.10.3 did not change playback or media preparation, so this result validates the update path only. Apple TV playback remains subject to the separate physical matrix above.

## 5. AirCiller 0.10.4 physical validation

The 0.10.4 candidate completed the physical Apple TV matrix on 30 and 31 August 2026:

- Direct Dolby Vision/HDR MP4 with E-AC-3 audio and selectable subtitles.
- HLS/fMP4 VOD with WebVTT subtitles.
- Picture, sound, subtitle selection, remote commands, long pause, resume, and seeking.
- Remote exit returned AirCiller to a stopped state without a ghost timer or false connection error.

The original media files were not modified.

## 6. Post-0.11.0 reliability candidate

Build 46 completed the remaining physical control checks on 1 September 2026:

- The Apple TV reported the natural end of a movie and AirCiller advanced once to the next Playlist item.
- Rapid pause, resume, forward seek and backward seek commands from the physical Apple TV remote, iPhone Remote and AirCiller remained synchronized.
- Stopping from AirCiller ended playback cleanly without reconnecting, requesting a new authorization code or leaving a ghost session.
- AirPlay remained linked throughout the command sequence.

The validation used the candidate app directly. It did not replace the installed app or modify the original media files.

## 7. AirCiller 0.11.2 Playlist keyboard validation

The candidate and installed build 48 were checked locally on 1 and 2 September 2026:

- Up and Down select a Playlist row without starting playback.
- Option-Command-Up and Option-Command-Down move the focused row and preserve focus.
- Move Up and Move Down are also available in the Playlist and contextual menus.
- The original Playlist order was restored after testing.

This change does not alter either playback route.

## 8. AirCiller 0.11.3 Playlist interaction validation

Candidate builds 51 and 52 were checked locally on 2 September 2026:

- The Playlist uses one native AppKit selection with no competing custom highlight.
- A single click selects a row without loading it or changing the current movie.
- Up and Down move the selection without affecting playback.
- Option-Command-Up and Option-Command-Down keep the moved movie selected, and the original order was restored after testing.
- Return and double-click use the existing explicit Playlist playback action.

The playback pipeline is unchanged. Physical Apple TV playback was not repeated for this interface-only release.

## 9. OpenSubtitles candidate

The initial OpenSubtitles candidate was checked locally on 2 September 2026:

- The standard OpenSubtitles file fingerprint is calculated from the file size and the first and last 64 KB.
- REST search and download requests include the required API key and AirCiller user agent.
- Search responses tolerate nullable metadata and preserve ASS, SRT and WebVTT format information.
- Credentials are stored as one serialized Keychain item and removed together.
- Search, empty-configuration and Settings screens were inspected in the built app.
- The full strict Swift 6 check suite and public repository audit passed.

The live OpenSubtitles check was completed on 3 September 2026:

- A real API key passed the connection check and was retained in Keychain without appearing in diagnostics or repository files.
- The service found no fingerprint match for the test Blu-ray and clearly switched to title results.
- The closest release match downloaded as a valid SRT file, was attached locally, converted to selectable WebVTT and displayed on the physical Apple TV.
- The downloaded subtitle remained in AirCiller's bounded local subtitle cache; the original movie was not uploaded or modified.

The OpenSubtitles integration itself does not change either Apple TV playback route.

## 10. Abandoned range reliability candidate

The local playback server regression test was extended on 3 September 2026 to reproduce the request pattern seen in the Mandalorian stall:

- It opens and abandons 160 partial requests against a sparse 5 GB movie.
- The process is restricted to 128 open descriptors during the test so that retained files or sockets fail quickly.
- Open descriptor usage returns to its baseline after the abandoned requests.
- A new partial request succeeds afterwards, confirming that the server remains usable.
- Local read failures now close the active playback session and report a recoverable error instead of leaving Apple TV loading indefinitely.

The strict local check suite passes.

## 11. AirCiller 0.12.0 physical reliability candidate

Build 53 completed the physical Apple TV reliability check on 3 September 2026:

- A 4K Dolby Vision Profile 8.1 movie played with its original E-AC-3 5.1 audio and selectable English subtitles.
- Picture, sound and subtitles were confirmed on the television.
- Pause, resume, chapter navigation and a burst of forward seeks remained synchronized without disconnecting AirPlay.
- The Apple TV requested new byte ranges throughout playback and reached the natural end without an endless loading state or a retained session.
- Two brief buffer waits after explicit resume and seek operations recovered automatically.
- The HLS/fMP4 route then played a Full HD H.264 movie with its original E-AC-3 5.1 audio, first with a selectable WebVTT subtitle and then with subtitles disabled.
- Picture and sound were confirmed in both HLS/fMP4 runs; subtitles appeared only in the selected-subtitle run, and changing the track preserved the playback position.

The original movies were not modified. The local and physical release gates are complete; GitHub CI remains required before tagging.

## 12. Reproducible performance fixtures

Run `./Scripts/benchmark_performance.sh` for optimized, synthetic measurements of ASS conversion and bounded process output. It reports all seven samples and their median, checks stable conversion and buffer output, and saves generated WebVTT alongside timings under `.build/performance/`. It does not use private media or install the app.

To compare an earlier implementation, pass a directory containing its `ASSSubtitleConverter.swift` and `ProcessDataBuffer.swift` as the first argument. Use the same compiler and fixture, run the versions sequentially, and compare their generated WebVTT with `cmp`. The fixture uses modern alignment; legacy SSA alignment is covered separately by the regression test because the original expression silently failed to compile.

These measurements cover 2,000 subtitle cues and 32 MiB of writes in 4 KiB chunks with a 1 MiB retained tail. They do not measure end-to-end playback, television compatibility, or battery consumption. The process buffer amortizes copying by retaining up to twice its configured byte limit internally; snapshots still expose at most the configured limit.

`./Scripts/check.sh` includes deterministic tests for buffer limits, compaction, retained snapshots, concurrent writes, legacy subtitle alignment, and concurrent conversions. Timing thresholds are intentionally excluded from CI.

## 13. Stability review candidate

The integrated checks passed on 5 September 2026. New coverage includes early process cancellation, obsolete authorization completions, unavailable Keychain reads, bounded HTTP responses, duplicate online results, invalid media/ASS times, sparse demand timestamps and malformed byte ranges. `StreamDiagnosticsSmokeTest` is now part of the required suite.

The candidate's bundled FFmpeg and Python imports were checked directly. A 60-second direct Dolby Vision sample passed packaging and AVFoundation asset checks with E-AC-3 audio and selectable subtitles.

The HLS/WebVTT sample passed packaging, duration and subtitle-group checks, but the local AVPlayer playback test returned AVFoundation -11848 / CoreMedia -15516. The unmodified published base returned the same error in this environment and produced byte-for-byte identical output. Do not describe local HLS decoding as passed or infer physical Apple TV playback from these results.

The empty window, library picker, non-playing Recents selection and loaded controls were inspected. Changing audio output and cancelling preserved the original selection when the tracks panel reopened. The Mac locked before the final Apply/reset check completed. That check, the final preview-corner adjustment and the full physical matrix remain pending. See [the review record](Docs/STABILITY_REVIEW.md). The installed app and stable feed are unchanged.

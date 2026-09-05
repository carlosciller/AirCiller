# Stability review

Review date: 5 September 2026. Base: published 0.12.0. Working branch: `stability/0.12.1`.

This records the review leading to 0.12.1, not a claim that the application has no remaining bugs. The original media, dependency lock and daily-use installed app were preserved throughout validation.

## Findings and changes

| Area | Finding | Change and regression coverage |
| --- | --- | --- |
| Process cancellation | An observer cancelled before waiting could leave an already-started helper running | Install termination handling before observing cancellation; test early cancellation and forced termination |
| Authorization | A delayed Keychain or authorization response could continue after Stop | One cancellable preflight owns the request; replacement and late-result tests |
| Credentials | Keychain errors were indistinguishable from missing credentials | Propagate read failures; test missing, unavailable and serialized access separately |
| Session lifetime | Old player callbacks and queued helper events could affect a stopped or replacement session | Check session and player-item identity; cancel pending start and pairing on Stop |
| Rapid seeking | Late seek replies and position reports could become the base of the next relative skip | Correlate each local helper reply with its request; bound position reconciliation; test interleaved replies, expiry and session reset |
| Helper shutdown | Natural completion could send Stop into a closed pipe and terminate the app with SIGPIPE | Skip redundant terminal commands; protect playback and pairing writes per descriptor; reproduce the unprotected signal and test recovery in subprocesses |
| Track editing | Changing a picker mutated active choices before Apply | Draft settings are committed on Apply; Cancel leaves playback choices alone |
| Online subtitles | Size checks happened after downloading the response | Bound JSON and subtitle bytes while reading, including unknown Content-Length; test cancellation and oversize responses |
| Search results | Duplicate IDs and extreme ratings could break result presentation | Deduplicate IDs and bound ranking input; synthetic API-response tests |
| Timing | Non-finite and oversized durations could reach integer conversions | Validate probe, chapter, display and ASS times; malformed-input regressions |
| Diagnostics | Sparse timestamps could trigger billions of empty window iterations | Visit only recorded windows; guard packet indices and byte-count overflow |
| HTTP | A malformed range start could be interpreted as a valid suffix request | Require an empty suffix start; test malformed and valid suffix ranges |
| Storage | Broad temporary-directory matching included unrelated AirCiller caches | Match the prepared-media UUID naming scheme; keep active subtitle-cache controls disabled |
| Dead code | Separate runtime download and installation code had no current UI caller | Remove the installer and its obsolete-only tests; retain bundled-runtime checks and archive build tools |

## Integrated performance audit

The separately supplied audit was already applied before this review resumed. It shares nine fixed ASS regular expressions, repairs legacy SSA alignment and amortizes process-buffer compaction. Its regression tests and benchmark script are retained.

Reported seven-run medians were 100.44 to 37.35 ms for 2,000 ASS cues and 102.36 to 4.23 ms for 32 MiB of bounded output. These are isolated synthetic measurements, not playback-speed or battery claims. The buffer may retain twice its configured size internally; snapshots respect the configured limit. See [the reproducible fixture](../TESTING.md#12-reproducible-performance-fixtures).

## Interface and documentation

Use a native segmented library picker, system List selection in Recents, semantic colors and text sizes, and a single playback-control material. Remove stacked custom glass backgrounds, the yellow background wash and overlapping control groups. Keep detailed stream measurements in the existing information popover.

The design follows Apple's [materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials) and [toolbar guidance](https://developer.apple.com/design/human-interface-guidelines/toolbars). README structure was reviewed against [IINA](https://github.com/iina/iina) and [Latest](https://github.com/mangerlahn/Latest): put the app, download and requirements first; keep contribution details separate.

The README now leads with use and setup, and links to an explicit compatibility guide. The roadmap separates active work, next candidates, research and blocked distribution work. Historical release prose is shorter without changing the original release dates or signed assets.

## Validation status

- Focused cancellation, preflight, credential, response-limit, result-decoding, ASS and timing tests pass locally.
- The complete integrated `Scripts/check.sh` passed, including strict Swift 6 compilation, simulated AirPlay, HTTP stress tests, publication checks and bundle signatures. The dependency lock reproduced without changes.
- FFmpeg 9.0.1 and the Python AirPlay imports were verified from inside the candidate bundle.
- A 60-second direct Dolby Vision sample retained original E-AC-3 audio and selectable text subtitles, and passed AVFoundation asset checks.
- A 60-second HLS/WebVTT sample passed packaging, duration and legible-track checks. Local AVPlayer playback failed with AVFoundation -11848 / CoreMedia -15516. Repeating with the published base produced the same error and byte-for-byte identical prepared files. This does not establish a new candidate regression, but local decoding is not a passed gate.
- The empty window, native library picker, non-playing Recents keyboard selection and loaded controls were inspected. Changing audio output and cancelling restored the original choice when the panel reopened. Applying +0.05 seconds of audio delay and -0.10 seconds of subtitle delay persisted both values when the panel reopened, without starting playback. Resetting and applying restored both to zero. The final preview corners and control layout were inspected in the built candidate.
- GitHub CI passed for both `d005f58` and the follow-up code commit `6a46dbe` on push and pull-request runs. See the candidate pull request for subsequent results.
- The user confirmed picture, original E-AC-3 5.1 audio, selectable English subtitles and remote pause/resume on the physical Apple TV with the direct Dolby Vision Profile 8.1 candidate. Stop returned the app to its idle state.
- Stop during HLS preparation returned to idle and a process check found no remaining FFmpeg process. A fresh preparation then started on an explicit Play request.
- The user confirmed picture, original E-AC-3 5.1 audio and selectable English WebVTT subtitles on the physical Apple TV for the HLS/fMP4 candidate. The app reported no buffer waits during the observed sample, despite a peak-demand warning; this is not a whole-movie network guarantee.
- The user also confirmed picture and original audio with HLS subtitles disabled. Applying this change resumed from the existing playback position, and the user confirmed subtitles were absent.
- The same candidate remained connected during a pause of about six minutes, retained its own automatic-sleep assertion and resumed without authorization. The user confirmed picture and sound after resuming. One additional buffer wait was recorded on resume.
- A rapid +10, +10, -10, -10 sequence exposed a position-reconciliation bug: all four commands were accepted, but stale feedback changed the base of a later skip. After the follow-up correction, the same sequence returned to the intended position on both HLS and direct Dolby Vision, with matching receiver acknowledgements. Pause/resume remained linked; the sequence was also repeated while Dolby Vision was playing. The original picture/audio confirmations above apply to `d005f58`; these seek checks used the corrected build.
- The full `Scripts/check.sh` suite passed again after the seek correction, including request-correlation and delayed-feedback regressions.
- The natural-completion check exposed an app exit immediately after the receiver's `ended` event. macOS recorded signal 13 (SIGPIPE). Cleanup tried to write Stop after the helper had closed its input. The regression test reproduces signal 13 with the old write and confirms a recoverable broken-pipe error with the protected writer.
- The complete `Scripts/check.sh` suite passed after both follow-up corrections. Physical completion was then repeated on `6a46dbe`: direct Dolby Vision ended and started the next HLS item once; HLS ended as the final Playlist item and returned to idle. The receiver reported both natural ends. The app retained the same process throughout, and closing it afterwards released that process and its sleep assertion. The original Playlist order was restored.
- These follow-up checks verify receiver events and application lifecycle. The earlier user-confirmed picture, audio and subtitle checks remain separately identified above.
- On a fresh launch, Stop was pressed while the UI showed the initial authorization check. The candidate remained idle afterwards and no bundled helper remained running. An explicit Play started preparation again without deleting credentials or renewing pairing. This checks the preflight cancellation boundary, not cancellation of a newly displayed PIN-pairing dialog.
- The user then confirmed picture, sound and selectable subtitles on the corrected direct Dolby Vision candidate, together with repeated pause/resume and forward/backward commands from the physical Apple TV and iPhone remotes. AirCiller remained synchronized and connected. This closes the planned physical checks for this review; it is not a claim about every file or device.

The direct and HLS packaging command builders and pinned engines are unchanged. Both paths were checked separately on the receiver. After acceptance, version 0.12.1 (build 54) passed the complete local suite again. Playback source and locked dependencies match the physically tested code in `6a46dbe`. Packaging and signed-update verification are separate distribution checks; the daily-use installed app is unchanged.

## Remaining risks

- OCR accuracy and complex ASS appearance still depend on the source and receiver rendering.
- Disconnected-drive library entries are currently removed on load; preservation is a separate roadmap item.
- Concurrent app copies do not coordinate ownership of temporary prepared-media directories. Do not run the test candidate beside an active daily-use copy.
- Title and artwork on the iPhone Lock Screen remain unreliable.
- Dependency proposals require a regenerated lock and engine validation; none were merged in this review.
- No Developer ID or notarization is claimed.
- While a local seek settles, an unrelated remote position can be deferred for up to two seconds after acknowledgement. Play/pause state continues to update; reconciliation expires after ten seconds if no acknowledgement arrives.

This review covers application state, authorization and processes, HTTP delivery, metadata and subtitle boundaries, storage, UI, dependencies and distribution. It does not certify third-party codec internals or every tvOS/device combination.

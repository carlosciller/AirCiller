# Stability review

Review date: 5 September 2026. Base: published 0.12.0. Working branch: `stability/0.12.1`.

This is a release-candidate review, not a claim that the application has no remaining bugs. The installed release, original media, dependency lock and signed update feed have not been replaced.

## Findings and changes

| Area | Finding | Change and regression coverage |
| --- | --- | --- |
| Process cancellation | An observer cancelled before waiting could leave an already-started helper running | Install termination handling before observing cancellation; test early cancellation and forced termination |
| Authorization | A delayed Keychain or authorization response could continue after Stop | One cancellable preflight owns the request; replacement and late-result tests |
| Credentials | Keychain errors were indistinguishable from missing credentials | Propagate read failures; test missing, unavailable and serialized access separately |
| Session lifetime | Old player callbacks and queued helper events could affect a stopped or replacement session | Check session and player-item identity; cancel pending start and pairing on Stop |
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
- The empty window, native library picker, non-playing Recents keyboard selection and loaded controls were inspected. Changing audio output and cancelling restored the original choice when the panel reopened. The final Apply/reset check was interrupted when the Mac locked, so it remains pending. A corner-clipping defect in the loaded preview was corrected; its final visual check is also pending.
- Current-branch GitHub CI must pass before release; see the candidate pull request for the current result.
- Physical Apple TV playback is pending. Previous 0.12.0 results do not validate this candidate.

The direct and HLS packaging command builders and pinned engines are unchanged. Shared lifecycle changes still require both playback paths to be checked on the receiver.

## Remaining risks

- OCR accuracy and complex ASS appearance still depend on the source and receiver rendering.
- Disconnected-drive library entries are currently removed on load; preservation is a separate roadmap item.
- Concurrent app copies do not coordinate ownership of temporary prepared-media directories. Do not run the test candidate beside an active daily-use copy.
- Title and artwork on the iPhone Lock Screen remain unreliable.
- Dependency proposals require a regenerated lock and engine validation; none were merged in this review.
- No Developer ID or notarization is claimed.

This review covers application state, authorization and processes, HTTP delivery, metadata and subtitle boundaries, storage, UI, dependencies and distribution. It does not certify third-party codec internals or every tvOS/device combination.

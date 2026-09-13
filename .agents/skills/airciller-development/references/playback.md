# Playback development and evidence

[ARCHITECTURE.md](../../../../ARCHITECTURE.md) defines the boundaries; [COMPATIBILITY.md](../../../../COMPATIBILITY.md) defines supported inputs and conversion limits. [TESTING.md](../../../../TESTING.md#3-physical-apple-tv-matrix) owns acceptance, and [Docs/PLAYBACK_CHECKS.md](../../../../Docs/PLAYBACK_CHECKS.md) owns runner commands, profiles and source approval. Read their applicable sections, not every historical run.

## Identify the actual path

Inspect `continueStart`, `diagnosticPlaybackRoute` and the affected track-change entry point in [StreamCoordinator](../../../../Sources/StreamCoordinator.swift). Verify the branch against the current code and probed/selected tracks:

| Normal startup condition | Preparation path |
| --- | --- |
| `info.isHDR` and `selectedSubtitle != nil` | `beginDirectHDRSubtitleStreaming`: direct MP4 with selectable subtitles |
| Otherwise, including HDR without a selected subtitle | `beginStreaming`: HLS/fMP4 VOD, with its separate HDR rendition handling |

The diagnostic label predicts selection; inspect prepared output to establish what was produced. Track changes can reselect the path. Test-only direct URLs do not define normal routing, and “HDR” in a filename does not establish either the route or rendered output. If routing changes, update this map with the code.

Keep Direct MP4 video-copy-only and HLS playlists finalized before playback. Preserve compatible original audio/layouts and selectable, unburned subtitles; unsupported-audio conversion requires explicit approval. Synthetic QA fixture encoding follows the separate development procedure in PLAYBACK_CHECKS and must not become an application fallback. Change only one packager per delivery; shared discovery, controls and HTTP code may affect both and require separate validation on each affected route.

## Debug the affected boundary

Start from the reproduction and inspect only the implicated stages: [MediaProbeService](../../../../Sources/MediaProbeService.swift), the coordinator, subtitle/OCR preparation, packaging, HTTP delivery, AirPlay control or output assessment. Correlate session/request identity, event order, cancellation ownership and the observed output. Do not infer a playback defect from a capture-source readiness failure.

Use the relevant domain record for non-obvious limits: [PGS](../../../../Docs/EXTERNAL_PGS.md), [VobSub](../../../../Docs/EXTERNAL_VOBSUB.md), [FLAC/layouts](../../../../Docs/FLAC_AUDIO.md), [transport streams](../../../../Docs/TRANSPORT_STREAMS.md), or [Vision CI](../../../../Docs/VISION_CI.md). For bitmap output, compare captured cues with the source bitmaps; OCR text alone does not establish correct television presentation.

Select deterministic regressions from the affected behavior and the existing [check script](../../../../Scripts/check.sh), using synthetic inputs or simulated bridge events. Cancellation and state fixes need relevant stale-result, cleanup and ordering cases. Timing measurements belong in repeatable benchmarks, not unstable CI assertions. Microbenchmarks do not measure first picture/audio on Apple TV; end-to-end comparisons need matched media, cache/connection conditions and observed output, as described in ROADMAP.

## Choose the required observation

Playback changes require the applicable local-media and Apple TV cases in TESTING, separately by route. Shared session/server changes require assessing both; engine upgrades require both. A basic three-clip batch is only a subset. Select affected track changes, long pauses, natural completion, commands from the specified remotes, cancellation, stop, replay and app-close cases. The receiver-free `cancelBitmap` profile proves local cancellation only.

| Evidence | Supports | Does not establish |
| --- | --- | --- |
| Deterministic/local | Strict build, simulated events, packaging/metadata, OCR, local AVPlayer and measured local fixtures | tvOS acceptance or television picture/sound |
| Receiver | Fresh receiver state/position, correlated command acceptance, observed requests/end events and cleanup, each recorded separately | ACKs, echoed targets and the Mac timer do not prove receiver progress; receiver state does not prove audiovisual output |
| Approved Apple TV digital capture | Sampled motion, non-silent digital audio and expected cues inside the recorded window | Physical speakers, Atmos layout, television HDR rendering, frame-accurate sync, physical remote use or whole-movie reliability |
| Physical observation | Picture, sound, track presentation and hardware/remote actions actually confirmed on the tested setup | Unobserved features, intervals, equipment or later candidates without an evidence-preservation comparison |

Hardware use does not automatically require manual watching: the approved runner can establish its documented receiver and sampled-output checks. Claims about physical HDR/Atmos, speakers or physical remotes still need the corresponding television/audio-chain or remote observation. Attribute user confirmations as such. Missing evidence stays unverified; contradictory evidence remains a failure. An offline reassessment must retain the original report and must not be described as a fresh live run.

## Run and retain evidence

Verify that the isolated check app matches the candidate's current inputs, following the rebuild/reuse criteria in [the build procedure](../../../../Docs/PLAYBACK_CHECKS.md#one-command-with-captured-output). A passing ordinary suite or an executable hash alone does not prove that an existing check-app bundle is current.

Follow that procedure with the approved receiver and a confirmed free TV. Reuse existing authorization where it covers the run; do not assert `--tv-is-idle` without that evidence. Preserve the installed app, daily preferences and original media. Root capture-source rules apply even to previews. Missing credentials/readiness blocks the requested batch; it does not authorize pairing, settings resets, another source or a silent downgrade to control-only acceptance. Continue independent local diagnosis and report the exact missing observation.

Record candidate commit/executable hash, route, relevant media/track properties, scenario, evaluator identity, result, cleanup and limits. Keep private plans, clips, frames and raw diagnostics in the documented ignored output location; publish only sanitized evidence. Retain failed runs and justify bounded retries. Historical passes cover their recorded candidate and observation window, not all of the current release matrix.

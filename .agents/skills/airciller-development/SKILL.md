---
name: airciller-development
description: Implement, debug and validate AirCiller changes, select the affected playback path, and assess release readiness from repository evidence. Use for AirCiller development tasks, not general media playback or unrelated projects.
---

# AirCiller development

Follow the repository's [AGENTS.md](../../../AGENTS.md). Run commands from the repository root. Links below are relative to this file; referenced documents keep their own relative links. Do not copy their procedures or historical acceptance records into this skill.

## Choose the relevant sources

Read the matching sections, not this entire document set on every task:

| Work | Read before deciding |
| --- | --- |
| Implementation and validation scope | [CONTRIBUTING.md](../../../CONTRIBUTING.md) and the applicable [TESTING.md](../../../TESTING.md) section |
| Playback, packaging, track selection | [ARCHITECTURE.md](../../../ARCHITECTURE.md), [COMPATIBILITY.md](../../../COMPATIBILITY.md), then the current coordinator and affected packager |
| Receiver, capture, cancellation or playback diagnosis | [Evidence and readiness](references/evidence-and-readiness.md), then the applicable [playback-check procedure](../../../Docs/PLAYBACK_CHECKS.md) |
| Bitmap subtitles | [External PGS](../../../Docs/EXTERNAL_PGS.md) or [VobSub](../../../Docs/EXTERNAL_VOBSUB.md); use the source bitmap for output comparisons |
| Audio layouts or transport streams | [FLAC](../../../Docs/FLAC_AUDIO.md) or [TS/MTS/M2TS](../../../Docs/TRANSPORT_STREAMS.md) |
| Credentials or library state | [Credential service](../../../Docs/CREDENTIAL_SERVICE.md) or [library recovery](../../../Docs/LIBRARY_RECOVERY.md) |
| Performance or compiler failures | [Performance fixtures](../../../TESTING.md#12-reproducible-performance-fixtures), the relevant [ROADMAP.md](../../../ROADMAP.md) phase, or [Vision CI](../../../Docs/VISION_CI.md) |
| Packaging, installation or publication | [Evidence and readiness](references/evidence-and-readiness.md#release-readiness), then [DISTRIBUTION.md](../../../DISTRIBUTION.md) |

Historical reports establish only their recorded candidate, cases and observations. Check the current diff and implementation before carrying evidence forward.

## Implement or debug

1. Identify the expected behavior, smallest reproduction, current commit and affected component. Inspect existing changes before editing. For a bug, preserve the initial failure and find the boundary at fault: probe, subtitle extraction/OCR, preparation, HTTP delivery, AirPlay control or output assessment.
2. Trace from [MediaProbeService](../../../Sources/MediaProbeService.swift) into [StreamCoordinator](../../../Sources/StreamCoordinator.swift), then only the affected service/helper. Use existing diagnostics and correlate request/session identity, event order and cancellation ownership; a Mac timer or helper ACK does not prove receiver progress.
3. Choose the path below before changing preparation. Reuse the existing test style and document the minimal invariant-preserving fix. Do not weaken a validator merely to make a failing media/receiver case pass. Compare an unchanged baseline when an environment or evaluator issue is suspected; preserve both results.
4. Add deterministic regression coverage for meaningful changed behavior: synthetic/public fixtures, simulated bridge events, explicit cancellation/stale-event cases as applicable. Locate the corresponding test command in [Scripts/check.sh](../../../Scripts/check.sh); keep private media and device identifiers outside tracked fixtures. Register new required smoke tests there when appropriate. Timing measurements alone are not stable CI assertions.
5. Run focused checks while iterating, then the contribution-policy gate. Documentation-only work ends with diff/reference checks. Executable changes require `./Scripts/check.sh`; bootstrap missing prerequisites using the repository scripts it identifies. Do not substitute an Xcode/SwiftPM build or a host playback engine. Dependency edits follow the lock regeneration procedure in CONTRIBUTING, never hand-editing `requirements.lock`.
6. For playback effects, apply [evidence and readiness](references/evidence-and-readiness.md) before claiming completion. Summarize changed behavior, exact checks, candidate identity and remaining gaps. Once required checks pass, stop unless a new concern warrants more work.

## Select and preserve the playback path

Use the current `StreamCoordinator` decision and the probed media/selected tracks, not a filename or the word “HDR” alone. At this revision, normal startup chooses:

| Condition | Path and inspection target |
| --- | --- |
| `info.isHDR` and `selectedSubtitle != nil` | `beginDirectHDRSubtitleStreaming`: direct MP4 with selectable subtitles; video must remain copy-only |
| Otherwise, including HDR without a selected subtitle | `beginStreaming`: HLS/fMP4 VOD; inspect its HDR rendition handling as well as the general HLS packaging |

Track changes may reselect the route. Trace the affected entry point and actual prepared output; test-only direct URLs are not the normal selection policy. Recheck this table against code if routing changes.

Preserve the root invariants and documented compatibility limits: no video encoding, no burned-in subtitles, original supported audio/layouts, and explicit approval for unsupported-audio conversion. Do not turn preservation of Dolby Vision/Atmos metadata into a claim of rendered HDR or physical Atmos output. All HLS playlists must be finalized before playback; keep direct and HLS packagers in separate deliveries. Shared discovery, controls and HTTP changes can affect both and need separate validation on each affected route.

A requested optimization that would break an invariant needs the separate design review described in ROADMAP, not a silent route fallback. The dedicated startup phase retains its maintainer checkpoint in AGENTS.

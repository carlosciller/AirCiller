# Roadmap

AirCiller should stay quick to open and dependable through a whole movie.
These are priorities, not a release schedule. New work needs a useful case and
a way to verify the result. [Compatibility](COMPATIBILITY.md) describes what
works today; [release notes](CHANGELOG.md) describe shipped changes.

## Published

- **0.18.4:** optional fallback subtitle language and ordered AirPlay helper
  shutdown before replacement playback. Published and installed through Sparkle;
  [release checks](Docs/RELEASE_0.18.4.md) include retained digital replay evidence,
  exact-commit CI, signed downloads and preserved library data.
- **0.18.3:** bounded library recovery with explicit restoration, duplicate-import
  feedback and correct mixed-import counts. Published and installed through
  Sparkle; [release checks](Docs/RELEASE_0.18.3.md) passed.
- **0.18.2:** stop and join unfinished bitrate analysis before direct preparation,
  clean up cancelled analysis, and label estimated peaks. Published download,
  signatures and CI verified. [Release record](Docs/RELEASE_0.18.2.md).
- **0.18.1:** smaller bundle without unused Python installers, verified build-time
  installer, and the reviewed zeroconf update. No playback-engine change.
  [Build maintenance](Docs/BUILD_PIP_MAINTENANCE.md).
- **0.18.0:** HDR startup and cancellation fixes, episode continuity, Playlist
  controls, track-panel corrections and opt-in private control.
  [Release record](Docs/RELEASE_0.18.0.md).
- Season folders, watched progress, OpenSubtitles search, TS/MTS/M2TS, supported
  FLAC soundtracks, local PGS/VobSub OCR and bounded media caches already exist.
  They are not future features.

## Next

Retain the original manual HDR Stop/replay timeout as an unexplained historical
failure. The independently reproduced helper-overlap defect is corrected, and
the directed digital replay checks pass. Do not claim that this proves the cause
of the earlier timeout. Investigate further if it recurs with new evidence;
there is no reason to repeat an unchanged passing batch now.

Next product candidates, in order:

1. Local opening/recap actions, only with a useful file carrying explicit chapter
   labels. Generic Chapter N entries do not establish safe skip intervals.
2. A season-level Continue action, after defining resume, watched/special episodes
   and manual-order behavior without changing selection or playback on navigation.
3. Readable episode titles, if concrete filenames justify parsing and correction.
   External artwork/metadata needs a separate privacy, provider and cache decision.

## After that, when there is a concrete need

| Work | Reason to start | Scope and limits |
| --- | --- | --- |
| Dependency maintenance | A security fix, compatibility fix or useful upstream change | Review callers and lock together; keep engines pinned and bundled |
| Bounded remote search | A real library becomes slow or responses become too large | Limit or paginate private-control results; no background index or media upload |
| Further startup work | A repeatable bottleneck and a specific alternative | Measure before changing code; preserve complete VOD and original media |
| Audio coverage | A useful unsupported file with a trustworthy reference | Qualify PCM precision/rates/layouts; full-length TrueHD 7.1 and 16-bit coverage remain incomplete |
| Subtitle coverage | A useful TTML/IMSC1, DVB or XSUB sample | Local, selectable output; specialized in-cue WebVTT timestamps still need seek coverage |

Dependency review on 28 October: [PR #44](https://github.com/carlosciller/AirCiller/pull/44)
updates multidict's input pin without its lock and fails CI. [PR #43](https://github.com/carlosciller/AirCiller/pull/43)
updates setup-node to a new major and passes CI. Both need independent review;
neither is included in 0.18.2. Keep protobuf 6.33.6 until a major update has a
concrete benefit and serialization/control evidence.

## Faster playback startup

The baseline and first targeted correction are complete. A large HDR sample
saved 6.729-10.206 seconds of local preparation when unfinished bitrate analysis
was stopped first. A smaller episode showed a variable benefit. Output bytes
were identical. These are preparation measurements, not time to first picture.
[Candidate evidence](Docs/REVIEW_2026_10_28.md).

Warm HLS preparation measured 0.566-2.279 seconds in three private-library
samples. One exceeded the ordinary 16 GiB cache and needed an isolated larger
limit for that experiment. A link-API alternative had no reliable worthwhile
saving, so it was not adopted. [Cache record](Docs/LIBRARY_STARTUP_MEASUREMENT.md)
and [direct-analysis baseline](Docs/DIRECT_DEMAND_MEASUREMENT.md).

The recorded 3.31-second receiver interval is not an established removable
delay. Capture added about 1.28 seconds in one comparison, not a universal
correction. Continuous audiovisual onset remains unverified where capture had
gaps. The receiver uses Wi-Fi 6 according to the maintainer; another network tour
or unchanged measurement run is not needed.
[Transport record](Docs/STARTUP_MEASUREMENT_2026_10.md).

A deeper engine or packager redesign needs a separate scope. Notify the
maintainer first so they can choose model and effort. Keep implementation
separate from testing/publication, and change at most one packager per delivery.
Preserve final duration, seeking, HDR/Dolby Vision, selectable subtitles and
original quality. External storage and bitrate peaks need their own hypothesis.
The [0.13.0 optimization record](Docs/STARTUP_OPTIMIZATION.md) is historical.

<a id="deferred-apple-shortcuts"></a>

## Parked or blocked

| Work | What would justify returning to it |
| --- | --- |
| DTS-HD MA lossless | Decoder guarantees or full qualification against an independent reference; damaged extensions can change samples without a hard failure. No silent core fallback or DTS:X promise |
| AV1/VP9, MPEG-2 and DCP | A demonstrated need for the maintainer's third-generation Apple TV 4K workflow; no video transcoder is planned |
| Apple Shortcuts | A signing/distribution decision: public ad hoc registration failed on the tested Mac. [Evidence](Docs/SHORTCUTS.md) |
| iPhone title and artwork | A reliable way to populate the Apple TV-owned Lock Screen card. Playback controls already work |
| Developer ID and notarization | Apple Developer Program membership. Sparkle signatures do not replace notarization |

Private control already opens and closes the app with the Mac awake, logged in
and screen locked. Remote wake/unlock and generic system-control tools are not
planned. [Scope](Docs/PRIVATE_REMOTE_CONTROL.md).

## Working limits

- Preserve original files and ask before audio conversion. No telemetry, cloud
  library or background indexing. The separately configured private-control
  relay/lifecycle agent is the only permanent-service exception.
- Keep the 165 MB logical bundle budget. Remove runtime files only with measured
  savings and applicable checks.
- Use [risk-based testing](TESTING.md#choose-checks-from-the-change). Reuse valid
  evidence, and reserve Apple TV sessions for affected behavior. Publication and
  installation have separate [distribution gates](DISTRIBUTION.md).

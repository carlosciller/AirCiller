# Local-library improvements goal

Started 2 November 2026 from `656b960`. Work remains local on an isolated candidate;
do not publish or install a version. Keep the macOS preparer and existing AirPlay
transport. No tvOS client, engine replacement or private-service deployment.

The deliveries stay in this order. A completed first delivery does not complete
the whole goal.

| Delivery | Required result | Current evidence/status |
| --- | --- | --- |
| 1. Continue Season | Visible episode/position; respect manual order, watched state and saved progress | Implemented and locally/native checked; targeted receiver and sampled output passed. [Evidence](SEASON_CONTINUATION.md) |
| 2. Intro/recap actions | Manual skip only from reliable explicit markers; no invented intervals | Implemented; strict/local/native checks and directed HLS receiver/captured output passed. No qualifying labels in the 17-file queue sample. [Evidence](CHAPTER_SKIPS.md) |
| 3. Playback information | Distinguish original format, performed conversion and verified output | Implemented; native EN/dark and ES/light detail review and split strict gate passed. [Evidence](PLAYBACK_INFORMATION.md) |
| 4. Episode presentation | Use concrete filename examples; preserve original name and allow presentation correction | Implemented; model/coordinator and strict build passed. Native Save/Cancel/Reset, invalid-name recovery, Undo/Redo and restart persistence passed in the isolated real view. [Evidence](EPISODE_PRESENTATION.md) |
| 5. Preparation waits | Change only a reproducible measured bottleneck | Reviewed current inputs against retained measurements. Demonstrated direct-analysis contention is already fixed; no new optimization justified. [Decision](LOCAL_LIBRARY_PERFORMANCE_REVIEW.md) |
| 6. Aether components | Assess specific components only for a real incompatibility or measured AirPlay benefit; reuse experiments | Reviewed pinned source, dependency resolution and both experiments. No dependency adopted; physical spatial output and comparative cost remain production gates. [Decision](AETHER_COMPONENT_REVIEW.md) |

Preserve originals, library and credential boundaries, explicit audio-conversion
decisions, both current video routes, pinned engines and their established limits.
Each delivery defines behavior and applicable checks before changing code. Record
local tests, native UI, receiver observations and sampled digital output separately.
Physical speakers, Atmos layout and HDR rendering require their own observations;
do not infer them from metadata or acknowledgements.

Only the previously approved exact Apple TV digital source may be captured. No
Mac/iPhone cameras or microphones. Do not reserve the television across independent
deliveries or repeat unrelated playback campaigns. Use TESTING.md's input comparison
and preserve failed/incomplete observations.

The goal finishes only after every delivery has a checked result or an evidence-led
conditional rejection/limitation, with no unverified required work disguised as
completion. This record is not release readiness or publication authorization.

## Completion audit, 2 November 2026

The six scoped results above are complete: deliveries 1-4 are implemented with
their selected local/native and applicable receiver evidence; delivery 5 adopts
no speculative optimization, and delivery 6 defers component integration on the
explicit evidence gaps in its review. Neither conditional review is presented as
a new speedup or a shipping audio capability.

The final ordinary code candidate is `ba358ea`; its executable SHA-256 remains
`05c123d038627a42e81f275c37c24b1972abf5e899f67e8f2d2771ddef50bfc1`.
The final native check added only temporary UI-check diagnostic messages, then
removed them. Production code matches that candidate; later edits are evidence
documentation only. The split strict gate and retained failures are enumerated
in [playback information](PLAYBACK_INFORMATION.md).

The original Continue Season and chapter capture reports were re-read separately;
their policy files still match their recorded hashes. Later changes add chapter
actions, completed-preparation information and Playlist display names, not new
packager, seek protocol, helper, server or runtime behavior. Existing route
evidence is reused on that comparison, not renamed as another device run.

No publication, version change, installation, pairing or private-service deployment
is part of this goal. The installed executable retains its original hash. Daily
library/preference comparison differs only in the recorded Sparkle last-check
timestamp; no claim is made that this independent timestamp stayed unchanged.
Test apps and capture processes are closed. Television output is sampled digital
evidence only; physical speakers, Atmos layout, HDR rendering, older macOS and
spoken VoiceOver retain their documented limits.

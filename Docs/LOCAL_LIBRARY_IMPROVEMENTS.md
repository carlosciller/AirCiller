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
| 4. Episode presentation | Use concrete filename examples; preserve original name and allow presentation correction | Implemented; model/coordinator tests and strict build passed. Native editor save/cancel/reset/restart remains unverified after automation lost its target. [Evidence](EPISODE_PRESENTATION.md) |
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

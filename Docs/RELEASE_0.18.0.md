# AirCiller 0.18.0

Version 0.18.0, build 69. Publication and local installation were authorized on
23 October 2026. This record is being completed as those stages pass; preparation
alone does not establish publication, deployment or native update acceptance.

## Scope and inherited evidence

The [October review](REVIEW_2026_10.md) records the source corrections, negative
controls, final strict local suite, native interaction checks and directed
Apple TV results. This release preserves that accepted production source,
resources, helper, locked dependencies and engine archives. Only release version
metadata and documentation change for distribution. Public ad hoc packaging and
the locally signed daily bundle have separate identities below.

Direct HDR passed with original HEVC/E-AC-3 and selectable subtitles on the exact
clip that reproduced the corrected preparation failure. HLS with WebVTT passed
separately. Pause, resume, rapid seeks, preparation cancellation and Stop/replay
cleanup are documented. Approved digital capture establishes sampled picture,
non-silent audio and expected subtitle cues, not physical HDR/Atmos rendering,
speaker layout or whole-movie reliability. No unrelated format matrix is repeated.

The installed private lifecycle passed open/status/close checks while macOS
independently reported screen lock. Deployment of the reviewed service-source
corrections requires its own before/after hashes and real connector checks.

## Distribution checkpoints

- Final public ad hoc strict gate and package: pending.
- Exact PR, merged-main and tag CI: pending.
- Signed archive/feed and published-byte verification: pending.
- Native Sparkle update in an isolated older copy: pending.
- Daily locally signed installation, version, preferences and library: pending.
- Private relay and lifecycle deployment with rollback: pending.

## Limits retained

No Developer ID or notarization is claimed. First-install Gatekeeper approval
may still be required. Public Shortcuts registration remains deferred. The private
connector is opt-in, separately provisioned and unavailable during system sleep
or logout; it provides no general filesystem, shell or unlock tool.

The review documents remaining minimum-window/stale-draft visual coverage and
the separate build-time pip trust-bundle maintenance. HTTP first-request telemetry
still includes local-preview requests and must not be called receiver-only timing.
No general Play-to-picture speedup is claimed.

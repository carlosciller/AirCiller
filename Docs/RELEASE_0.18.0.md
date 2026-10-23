# AirCiller 0.18.0

Version 0.18.0, build 69. Publication and local installation were authorized on
23 October 2026. This record is being completed as those stages pass; preparation
alone does not establish publication, deployment or native update acceptance.

## Scope and inherited evidence

The [October review](REVIEW_2026_10.md) records the source corrections, negative
controls, final strict local suite, native interaction checks and directed
Apple TV results. This release preserves that accepted app source,
resources, helper, locked dependencies and engine archives. Release version
metadata and documentation change for distribution; the independently deployed
relay also has the listener correction described below. Public ad hoc packaging and
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

- Final public ad hoc strict gate and package: passed, including strict Swift 6,
  warnings-as-errors and 13 private-control tests. The final log is retained
  locally as `.build/release-0.18.0/public-check-final.log`.
- Exact source PR CI: [39959273988](https://github.com/carlosciller/AirCiller/actions/runs/39959273988)
  passed in full mode for `6869bada52dc1c4083947e9cd0b985a8dedb75ca`.
  [PR #38](https://github.com/carlosciller/AirCiller/pull/38) merged as
  `4785d4c41c3c87d3d28288294cf6abed9d1df9e9`. Merged-main and tag checks are pending.
- Signed archive, delta and feed: signatures verified with the pinned Sparkle
  tools. Published-byte verification is pending publication.
- Native Sparkle update in an isolated older copy: pending.
- Daily locally signed installation, version, preferences and library: pending.
- Private relay and lifecycle deployment with rollback: passed; see below.

The tagged record captures preparation. The [current verification record](https://github.com/carlosciller/AirCiller/blob/main/Docs/RELEASE_0.18.0.md)
also records the publication and installation completed after the tag.

### Accepted artifacts

The public app is ad hoc signed and has 154,613,985 logical bytes, below the
165 MB limit. Its executable SHA-256 is
`e53a6425c6df5f1f94d18a3ba3cfb457e141df27935cf44c444a01a3dfafd118`.
The separately built local app has 154,691,708 logical bytes; its executable is
`8bbfedf3db0b197fd664251b9117978e5a29ab7e1685f115b645805aa5572a73`.
Both bundles passed strict code-signature verification. The local credential
service is byte-identical to the previously authorized installed service.

| Asset | SHA-256 |
| --- | --- |
| AirCiller-0.18.0-69.zip | `dca9e85ccf42f6dc0a66c0bf3bdf252859fe7bc1a36f9d0a50441f83733323b2` |
| appcast.xml | `ccaacdf12404d535290355e08f3bae8ea38f68a408f7d92d805f7fe2c7952584` |
| AirCiller69-68.delta | `01bd5c09ba3e5ac388d3117532e4971d34cf9b0b1bd2298a6d1fa4fcbed02dce` |

### Private service deployment

The relay and lifecycle agent were updated independently, preserving their
previous sources, existing configuration, credentials, tunnel and native helper.
The service runtime was not upgraded. Its actual Node runtime passed the 12
standalone tests; the thirteenth, native-coordinator integration test passed in
the Mac's strict gate.

The first post-deployment status request timed out. Inspection established that
the relay had bound its own Bonjour hostname to loopback after restart. The
correction resolves that hostname against actual non-internal local interfaces
and fails closed if no usable address exists. It does not bind all interfaces
or alter network settings. Regression tests cover loopback-first resolution,
eligible IPv4/IPv6 and rejected addresses. The corrected listener and deployed
file hashes were checked on the server.

Real connector requests then established closed → running → idle → closed,
with independent process checks. Repeating an open request with the same
operation identifier returned the cached result. No movie was started. These
are fresh deployment checks, not new locked-screen or iPhone-originated tests;
the earlier locked-screen evidence applies to the unchanged native helper.
Final verification against the newly installed daily app remains pending.

## Limits retained

No Developer ID or notarization is claimed. First-install Gatekeeper approval
may still be required. Public Shortcuts registration remains deferred. The private
connector is opt-in, separately provisioned and unavailable during system sleep
or logout; it provides no general filesystem, shell or unlock tool.

The review documents remaining minimum-window/stale-draft visual coverage and
the separate build-time pip trust-bundle maintenance. HTTP first-request telemetry
still includes local-preview requests and must not be called receiver-only timing.
No general Play-to-picture speedup is claimed.

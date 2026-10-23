# AirCiller 0.18.0

Version 0.18.0, build 69. [Published](https://github.com/carlosciller/AirCiller/releases/tag/v0.18.0)
and locally installed on 23 October 2026, with the maintainer's authorization.
The private relay and lifecycle corrections were deployed separately. Native
updating and the installed app's connector checks passed as recorded below.

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

The previously installed private lifecycle passed open/status/close checks while
macOS independently reported screen lock. The service deployment below has its
own before/after hashes and real connector checks; it is not a new screen-lock test.

## Distribution checkpoints

- Final public ad hoc strict gate and package: passed, including strict Swift 6,
  warnings-as-errors and 13 private-control tests. The final log is retained
  locally as `.build/release-0.18.0/public-check-final.log`.
- Exact source PR CI: [39959273988](https://github.com/carlosciller/AirCiller/actions/runs/39959273988)
  passed in full mode for `6869bada52dc1c4083947e9cd0b985a8dedb75ca`.
  [PR #38](https://github.com/carlosciller/AirCiller/pull/38) merged as
  `4785d4c41c3c87d3d28288294cf6abed9d1df9e9`; its
  [merged-main check](https://github.com/carlosciller/AirCiller/actions/runs/39960760457)
  passed in full mode. Documentation follow-up #39 passed in docs mode on
  [PR](https://github.com/carlosciller/AirCiller/actions/runs/39961644540) and
  [main](https://github.com/carlosciller/AirCiller/actions/runs/39961857083).
  Tag `v0.18.0` points to `37b421758d14dcb5a70ad4a7d47695d466086b8f`;
  its separate [tag CI](https://github.com/carlosciller/AirCiller/actions/runs/39962124149)
  passed in full mode. No required release check was skipped or treated as passed
  while pending.
- Signed archive, delta and feed: signatures verified with the pinned Sparkle
  tools and the public key embedded in the accepted app. Anonymous HTTPS
  downloads matched the hashes below, with only trusted GitHub asset redirects.
  The latest-feed URL returned this feed. The extracted public bundle matched
  the accepted bundle's file bytes, modes and symlinks and passed strict signing
  verification. Published notes and the release body match the reviewed notes.
- Native Sparkle update: passed in an isolated public 0.17.3 (68) copy. Check for
  Updates displayed 0.18.0 and the reviewed notes; Sparkle downloaded the 478 KB
  delta, offered Install and Relaunch, and restarted at the same isolated path.
  About displayed 0.18.0 (69). The resulting bundle exactly matched the full
  published package, including file bytes, modes and symlinks. The transient
  UI handle expired during relaunch; an independent process check confirmed
  the new process before the UI was reattached. This was not a copied-bundle test.
- Daily locally signed installation: passed. About displays 0.18.0 (69), and
  the running process belongs to the intended installed bundle. Playlist,
  recent items, seasons, language and private-control preference match the
  pre-install snapshot; no movie was opened or played. Settings reports the
  private connector Connected. The previous daily app is retained as rollback.
  After the isolated update, the only changed preference was Sparkle's last-check
  timestamp. The test copy was closed and the installed daily app reopened
  through the real connector; fresh status was idle, with no conversion pending.
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
The newly installed 0.18.0 daily app also passed open → idle → close → closed,
with its installed process appearing and disappearing. The home relay and tunnel
remained running, and anonymous MCP requests still returned HTTP 401. No new
credentials, Keychain grants or network-setting changes were needed.

The unrelated zeroconf update in PR #30 is not included. Its
[failed check](https://github.com/carlosciller/AirCiller/actions/runs/39961144069)
was inspected: the generated dependency lock differs from the committed file.
The failure remains visible; the release retains the accepted locked version.

## Limits retained

No Developer ID or notarization is claimed. First-install Gatekeeper approval
may still be required. Public Shortcuts registration remains deferred. The private
connector is opt-in, separately provisioned and unavailable during system sleep
or logout; it provides no general filesystem, shell or unlock tool.

The review documents remaining minimum-window/stale-draft visual coverage and
the separate build-time pip trust-bundle maintenance. HTTP first-request telemetry
still includes local-preview requests and must not be called receiver-only timing.
No general Play-to-picture speedup is claimed.

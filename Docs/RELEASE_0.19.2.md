# AirCiller 0.19.2 release record

Published: 0.19.2, build 76, on 10 November 2026 (Europe/Madrid).
[Release](https://github.com/carlosciller/AirCiller/releases/tag/v0.19.2).
Native updater installation remains pending; the daily app was not replaced.

## Scope and evidence reuse

PR #58 merged as `8d1e912`, with the same tree as its accepted head `7e6158c`.
Its [full CI](https://github.com/carlosciller/AirCiller/actions/runs/42715538855)
passed. The [quality review](QUALITY_COMPLETION_2026_11.md) records the scoped
direct-cache miss/hit/invalidation, terminal bitmap on both routes, unchanged
remote controls and cleanup checks. The English/Spanish cache settings were
inspected. The [identity repair](LOCAL_NETWORK_TEST_IDENTITY.md) records signed
test staging, discovery, noninteractive credential access and recompilation.

Release preparation changes only version/build metadata and prose. Production
source, resources, helpers, locked runtimes and dependencies match that accepted
candidate. No Apple TV tests are repeated. Sampled digital output is not a claim
of physical HDR/Atmos or frame-accurate subtitle endpoints.

At the maintainer's request, reuse the completed strict local tests and compile
the versioned public-signing artifact once, followed by the existing publication,
bundle and signature assertions. This is a resumed release gate, not a claim of
a second full-suite invocation. CI independently evaluates the exact release tree.

The daily app includes separately managed local integrations. Verify native
Sparkle using an isolated older copy with discovery suppressed, preserving daily
app, library and preferences. Do not create another Local Network authorization
or change the established daily credential service for an updater check.

## Completed distribution checks

- Versioned public-signing build and bundle assertions passed, ending
  `AirCiller local checks: OK` in `.build/release-0.19.2-check.log`. Earlier
  unchanged tests were reused as described above, not rerun locally.
- Bundle: 146,164,618 logical bytes, below the 165 MB limit. Deep strict signature
  verification and bundled-Python tests pass. All 97 Sparkle file/symlink entries
  match the pinned framework. The distribution audit retains the four expected
  ad hoc limitations: no Developer ID, Hardened Runtime, notarization or
  Gatekeeper acceptance.
- Executable SHA-256:
  `2f58fcd7fd66f1c9b24e23019bfe241f8462822c73c7109895a4365375620c67`.
- ZIP: 59,316,205 bytes, SHA-256
  `42e1d27c45099a14d1bc24c1f7483575373d2db3f25c6c9cf02677dec9aaecd2`.
- Sparkle generated and signed the full archive and feed with the existing key.
  No deltas or historical asset replacements. Unauthenticated downloads of all
  three assets match the reviewed local bytes, including the latest-release feed.
  Public-key verification of both downloaded signatures passes. Extracted app
  signature, executable and version match; GitHub and packaged notes agree.
- [Release PR #59](https://github.com/carlosciller/AirCiller/pull/59) passed
  [full CI](https://github.com/carlosciller/AirCiller/actions/runs/42718516940)
  for `3d2bc1badd67311236fa3e9ed25bb04320207b27`.
- Merge `94267c4f3265cbd98808edd23408e6fab6d8a8a0` has the identical tree.
  [Main CI](https://github.com/carlosciller/AirCiller/actions/runs/42719990045)
  and [tag CI](https://github.com/carlosciller/AirCiller/actions/runs/42720039658)
  both passed in reuse mode before publication. Tag `v0.19.2` targets that merge.

## Native updater boundary

An older public copy and a private preferences snapshot are prepared under
`.build/updater-0.19.2`. The daily app was observed with a paused receiver session.
Permission to close it was requested; no answer had arrived at this checkpoint.
No test copy was launched, no playback was stopped, no new Local Network entry
was requested and no installed app was replaced. Complete native Sparkle
download/install/relaunch once that session can safely be closed. Published-byte
and signature verification is complete, but is not native-updater acceptance.

Private verification evidence is retained in `.build/release-0.19.2-verification`.

DTS-HD MA lossless, intermittent multicast discovery and the closed Aether
presentation-timing experiment are not claimed as fixed. Developer ID and
notarization remain unavailable under the existing distribution policy.

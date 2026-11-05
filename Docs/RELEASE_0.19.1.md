# AirCiller 0.19.1 release record

Published: version 0.19.1, build 75, on 5 November 2026.
[Release](https://github.com/carlosciller/AirCiller/releases/tag/v0.19.1).
The maintainer will update the installed app separately; no installation was
performed as part of this task.

## Scope and reused evidence

The [maintenance review](MAINTENANCE_2026_11.md) updates certifi from 2026.10.19
to 2026.10.23. Only two roots and the package version changed upstream. The new
DER-fingerprint regression fails on the old bundle and passes on the new one;
the lock is generated with the pinned compiler. Multidict and setup-node remain
unchanged. No source, playback helper, media runtime, UI resource or workflow
changes are included. Version/build metadata and these notes complete the scope.

The CA bundle belongs to Requests; its reviewed callers do not change the
local HTTP delivery or either packager. No new receiver session is required.
The direct/HLS playback evidence recorded for 0.19.0 remains applicable at those
unchanged boundaries. This is evidence reuse, not new television observation or
a promise about every external HTTPS service. Rejected chains anchored only in
removed roots must not be accepted by bypassing TLS verification.

The bounded search review found no worthwhile optimization for the current
library. No performance improvement is advertised by this release.

## Completed distribution checks

- Final versioned ad hoc gate passed in one invocation:
  `.build/release-0.19.1-check.log`, ending `AirCiller local checks: OK`.
  The accepted build was packaged without another build.
- Signed bundle: 146,119,403 logical bytes, below 165,000,000. Signature
  structure, bundled runtimes and the three packaged-Python regressions pass.
  The distribution audit reports only the four existing ad hoc limitations:
  no Developer ID, Hardened Runtime, notarization ticket or Gatekeeper acceptance.
- Executable SHA-256:
  `62de35545cf55e65fa2c45ffa7eb23b03f73f0b0db2086ca1d608a4df0e6baaa`.
- ZIP `AirCiller-0.19.1-75.zip`: 59,300,988 bytes, SHA-256
  `4392bae5bee859c72922a9a75311e07b133fb052ed342600344c38ad1422da4f`.
- Sparkle generated the full-update feed with the existing AirCiller key.
  This release supplies the full archive, notes and signed feed; no deltas.
  The public key matches the extracted app. Feed and archive signatures pass.
- Unauthenticated downloads of all three assets match reviewed local bytes;
  the latest-release feed matches too. Redirects remain HTTPS on GitHub asset
  hosts. GitHub body and packaged/downloaded notes match the reviewed notes.
- The extracted public app reports 0.19.1 (75), matches the accepted executable
  and passes deep strict signature verification. All 97 Sparkle framework
  inventory entries, including symlinks and signed nested files, match the
  pinned distribution.

## Exact-commit CI and publication

- [PR #55](https://github.com/carlosciller/AirCiller/pull/55) passed
  [full CI](https://github.com/carlosciller/AirCiller/actions/runs/42014964936)
  for `b2cb94f1f8bfda19e05109901c97732a9c367116`.
- Squash merge `03f05801a7bf82e81052ae85560e2a3f7f165a91` has an identical tree.
  [Main CI](https://github.com/carlosciller/AirCiller/actions/runs/42016581791)
  passed in reuse mode against that full-check evidence.
- Tag `v0.19.1` points to the same merged commit. Its separate
  [tag CI](https://github.com/carlosciller/AirCiller/actions/runs/42016635819)
  also passed in reuse mode before publication.
- Three assets were staged in a draft, checked, then published at 11:10:21 UTC
  as the latest release. Historical archives and feeds were not overwritten.
  Dependency-only PR #52 is superseded by #55; #51 and #43 remain deferred.

Private logs and public verification results remain under
`.build/release-0.19.1-verification`. Installation and a native Sparkle
download/install/relaunch were deliberately not performed: the maintainer
chose to update manually. Published signatures/byte identity are verified;
installed-update acceptance is not claimed.

The earlier maintenance gate and its documentation-only retry are recorded in
the maintenance review. They do not substitute for this final versioned release
gate. No original media, daily library, credential service or separate Movistar
Cloud changes belong to the candidate.

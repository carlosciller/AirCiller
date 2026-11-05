# Maintenance candidate after 0.19.0

Candidate review, 5 November 2026. Base: `9123b9b`. No publication,
installation or private-service deployment is included. The separate Movistar
Cloud working changes are not part of this checkout.

## Validation selection before implementation

- Certifi #52: the upstream change removes the emSign C1/C3 roots and changes
  the version, with no Python logic changes. Add an offline DER-fingerprint
  regression and demonstrate failure on the old bundle, success on the new one.
  Preserve the existing compromised-root and Requests bundle tests. Regenerate
  the lock using the pinned compiler and review its complete diff.
- Certifi is bundled through Requests. pyatv uses Requests' case-insensitive
  dictionary in HTTP support and Requests for RAOP remote audio fetching.
  The change does not modify local AirPlay HTTP delivery, packagers or decoding.
  Validate imports and SSL trust loading; no unrelated receiver matrix is needed.
- Multidict #51: review major-version compatibility and benefit; do not include
  merely to clear Dependabot. Its dictionaries are used by aiohttp/yarl on the
  shared transport boundary. The deferral decision is recorded below.
- setup-node #43: review current action inputs/runtime. CI-only; no Apple TV
  test is justified by this action alone. The deferral decision is below.
- Final candidate: focused regressions during iteration, then the complete
  `Scripts/check.sh` strict gate once. Any later performance change requires
  a separate selection of affected cases before implementation.

## Sources

- https://github.com/certifi/python-certifi/compare/2026.10.19...2026.10.23
- https://github.com/aio-libs/multidict/releases/tag/v7.2.1
- https://github.com/actions/setup-node/releases/tag/v7.0.0
- https://github.com/actions/setup-node/releases/tag/v6.5.0
- https://github.com/aio-libs/multidict/blob/v7.2.1/CHANGES.rst

## Certifi focused results

The new two-root regression fails on the original 2026.10.19 vendor bundle
(both fingerprints present) and passes on 2026.10.23. All five dependency
security checks and eight aiohttp/pyatv ownership checks pass on the candidate.
The regenerated lock changes only certifi's version and its two archive hashes.
The host Python is now 3.13.16; compilation of the lock used the pinned bundled
3.13.15 interpreter instead, without relaxing the compiler-version check.
Pinned engine and Sparkle archives were freshly downloaded and verified in this
isolated checkout; installed-app resources were not copied or modified.
This is focused local evidence, not the final strict gate or receiver evidence.

## Remaining dependency decisions

**Multidict #51: defer, retain 6.9.1.** aiohttp 3.14.5 allows `<8.0,>=4.5`
and yarl 1.25.1 allows `>=4.0`, so package metadata does not block 7.2.1.
However, upstream 7.1 changes keys/iteration to distinct keys while items and
length still include duplicates; it also changes string-subclass normalization.
These are substantive changes in a shared HTTP component, not a harmless lock
repair. Its smaller tables and microbenchmark improvements have no demonstrated
startup benefit in AirCiller. The 7.2.1 proxy fix addresses a 7.2.0 regression,
not a reproduced defect in the retained 6.9.1. Revisit for a relevant security or
correctness issue, or measured HTTP dictionary cost. Qualification must cover
duplicate headers/query parameters, casing, proxy construction, aiohttp/yarl,
session cleanup and the affected direct/HLS receiver controls. No claim that
7.2.1 is incompatible or has passed those checks is made. Its existing PR remains
unchanged, with a failing stale lock; it must not be merged as-is.

**setup-node #43: defer, retain v6.** Both current v6 and v7 actions use Node 24;
AirCiller supplies only the relative `.node-version` input (24.19.0), without
registry authentication, mirrors or explicit package caching. v7 adds cache-key
outputs, ESM implementation and authentication/mirror fixes, none needed by this
workflow. The maintained v6 line already includes cache 5.1.0/security overrides
in its upstream release notes. No observed v6 failure requires the major change.
The old PR's green check is not validation against current main. Revisit for a
security fix unavailable on v6, an input feature needed here or v6 retirement;
validate CI selection and the actual hosted job then. No application or receiver
test is warranted for the action alone. No action or PR was modified.

## Bounded performance review

Reviewed HistoryStore loading (bounded recent list and one queue/season decode),
RemotePlaybackControl search (in-memory queue, no disk scan), loadVideo selection
(probe with cancellation/session ownership), and PreparedMediaCache checkout
(validated metadata plus hard links for media). Do not remove integrity checks
or cache probe results without a source-change invalidation case. Existing
preparation evidence remains in `LOCAL_LIBRARY_PERFORMANCE_REVIEW.md`; the cache
source still matches `5886fee`, and all production Sources match 0.19.0.

The selected hypothesis was repeated season lookup in RemoteLibraryIndex.search.
A read-only optimized Swift harness exercised the real function with the actual
17-item, one-season preferences and synthetic 1,000-item/100-season inputs.
It emitted counts/timings only, never paths, titles or private identifiers.
Each case used seven samples of 100 calls, verifying exact result equality on
every call. No production code was changed and no alternative speedup is claimed.

| Case | First call (ms) | Median (ms) | Sample range (ms) | Response bytes |
| --- | ---: | ---: | ---: | ---: |
| Actual library, missing title | 2.038 | 0.0328 | 0.0297 to 0.0403 | 2 |
| Actual library, matching title | 0.116 | 0.0291 | 0.0277 to 0.0322 | 271 |
| Actual library, matching season | 0.052 | 0.0448 | 0.0407 to 0.0470 | 2,693 |
| Synthetic 1,000, no match | 2.663 | 2.5243 | 2.3880 to 2.5811 | 2 |
| Synthetic 1,000, all match | 4.541 | 4.5359 | 4.3353 to 4.6204 | 172,791 |

Process peak RSS was 10,715,136 bytes across all cases. These are in-process
search-plus-equality timings (encoding measured only for response size), not
relay round trips, app launch, preparation or first picture. First call includes
lazy process/framework initialization; this is not an OS-cold disk benchmark.
No media/app cache was populated or evicted. A tiny actual-library cost does not
justify an index or extra invalidation state. Large response pagination remains
conditional on actual usage, not the synthetic stress size alone.

Retained local evidence: `.build/performance/run.CMVCAl/` contains the harness,
production source hashes, all samples and resource results. The storage guard
removed its generated executable, retaining the report; the isolated `.build`
used 0.28 GiB at completion. No Apple TV session was necessary.

## Candidate environment and limits

macOS 27.2 build 26B123, arm64, Apple Swift 6.4.2. Active developer tools are
Command Line Tools, not full Xcode (`xcodebuild -version` is unavailable).
Node 24.19.0 and bundled Python 3.13.15 are supplied explicitly to the local
gate. No host interpreter or engine upgrade was performed.

The trust-store change intentionally rejects chains anchored only in the two
removed roots; never bypass certificate verification to restore such a chain.
This review does not establish availability of every external HTTPS endpoint.
The candidate has no new remote-playback, physical HDR/Atmos, UI or hosted-CI
acceptance claim. No source in `Sources/`, playback helper, engine, UI resource,
build configuration or workflow changed from the published 0.19.0 base.

## Final validation and handoff

All deterministic/code checks in `Scripts/check.sh` passed, including strict
Swift 6 typechecking, dependency security, ownership, local media, private-control
and capture-tool compilation. No capture source was opened. The first invocation
stopped at the publication-text check because this report and ROADMAP used long
dash characters in numeric ranges. That failure remains in
`.build/maintenance-full-check.log`.

Only those prose ranges changed after the successful code checks. Rather than
rerunning them, the exact remaining tail of the unchanged check script was
executed from `check_publication.sh` through application build, required bundle
contents, deep strict signature verification and bundled-Python regressions.
It exited 0 with `AirCiller local checks: OK`; the transcript is
`.build/maintenance-check-tail.log`. This is a completed staged validation,
not a claim that the original failed invocation exited successfully.

The built review candidate is `.build/AirCiller.app`; it was not launched or
installed. Its bundled certifi imports as 2026.10.23. The standard bundle audit
reports 146,119,403 logical bytes against the 165,000,000-byte budget. Isolated
`.build` occupies about 1.1 GiB. Full source/runtime identity checks show no
playback change beyond the reviewed CA data, so no new receiver session or
repeated 0.19.0 playback batch was necessary. No current hosted-CI run is claimed.

Next step: review this local candidate, then authorize submission/integration
and the separate release/install procedure if desired. Original PRs, the daily
app, credentials, media and separate Movistar Cloud checkout were not modified
by this work. Publication and installation remain outside this goal.

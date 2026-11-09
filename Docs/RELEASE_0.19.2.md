# AirCiller 0.19.2 release record

Candidate: 0.19.2, build 76. Publication and native update are authorized.
Status: preparing; no publication or installation claimed by this checkpoint.

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

Remaining gates: versioned public build/package audit; exact-commit release PR,
main and tag CI; signed appcast/archive; unauthenticated published-byte identity;
native download/install/relaunch on the isolated copy. Keep each outcome separate.

DTS-HD MA lossless, intermittent multicast discovery and the closed Aether
presentation-timing experiment are not claimed as fixed. Developer ID and
notarization remain unavailable under the existing distribution policy.

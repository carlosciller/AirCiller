# AirCiller 0.19.1 release record

Candidate: version 0.19.1, build 75. Publication is authorized subject to the
release gates below. The maintainer will update the installed app separately;
no installation is part of this task.

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

## Release gates

Before publication: run the final public ad hoc strict check after versioning;
audit the actual signed bundle and its size, preserving Sparkle's signatures;
package that accepted build and sign the archive/feed with the existing key;
verify PR, exact merged-main and tag CI; verify published bytes, signatures,
notes and extracted package. Record the completed results in a follow-up.
The existing absence of Developer ID and notarization is unchanged.

The earlier maintenance gate and its documentation-only retry are recorded in
the maintenance review. They do not substitute for this final versioned release
gate. No original media, daily library, credential service or separate Movistar
Cloud changes belong to the candidate.

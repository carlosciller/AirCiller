# AirCiller 0.18.2 release record

Status: release preparation, not yet published. Build 71. No installation or
private-service deployment is authorized in this delivery.

## Scope and evidence

The executable changes are the three corrections in the
[28 October review](REVIEW_2026_10_28.md): stop and join unfinished demand analysis
before direct preparation, retire cancelled analysis safely, and distinguish
estimated diagnostic peaks. No packager, engine or dependency is changed.

The same day's captured direct HDR and HLS subtitle checks, preparation
cancellation, receiver Stop/replay/clean exit and native diagnostic checks are
retained. Production Sources, Resources, helpers, locked dependencies and build
configuration are compared with candidate commit `31990e9`. Release version/build
and packaged notes change, not playback behavior. This is reused evidence, not a
new receiver session. See the review for sample limits and report identities.

The full local release gate is required after versioning. PR, main, tag, public
archive and signed-feed verification will be recorded after they complete.

## GitHub audit, 28 October

| Finding | Evidence and decision | Verification |
| --- | --- | --- |
| README mixed setup with advanced integration | Put requirements beside download, explain which ZIP to choose, separate compatibility and help, shorten private-control description | Review links and rendered GitHub page before closure |
| Feature template claimed there was no permanent service at all | Qualify ordinary playback versus separately configured private control | Compare PRIVACY and private-control guide |
| Bug template used an old version example | Ask for the actual About version and build | Template diff |
| Roadmap mixed completed campaigns and future work | Separate published, recovery next, evidence-triggered follow-ups and blocked work | Cross-check code and dated review; preserve existing anchor links |
| Dependency PR #44 fails; #43 passes | #44 changes requirements.in without the lock; #43 is setup-node major 7. Both stay separate from this release | Read diffs and CI; no tests weakened or majors merged |
| Recent release prose | 0.18.1 is already concise; retain it. Group 0.18.0's existing facts for readability without changing signed assets | Compare public prose with original versioned notes |
| Private data and oversized history objects | Scan all 1,283 reachable blobs (20.3 MB total) for private-key/token patterns and personal paths; no secret match. Path matches are checker regexes. No blob exceeds 5 MB | Pattern scan is bounded evidence, not proof that every possible secret is absent |
| Licensing, privacy and attribution | GPL-3.0, original artwork, dependency notices, local OCR, optional metadata relay and Codex attribution are documented | Retain notices and package licensing checks |

Editorial references: [IINA](https://iina.io/) and its
[repository](https://github.com/iina/iina), and
[Transmission](https://transmissionbt.com/) and its
[repository](https://github.com/transmission/transmission). Adopt download and
requirements near the top, direct task descriptions and separate contributor
documentation. No copied assets or branding. No new screenshot is added: a
current sanitized full-app capture is not part of this publication candidate.

CI retains read-only token permissions, a required completion check and
fail-closed evidence reuse. Dependabot's major proposals remain visible and
are not merged for tidiness. No repository permission, protection, tag deletion or
history change is part of the audit. Pinned engine assets hosted under v0.10.3
must remain available.

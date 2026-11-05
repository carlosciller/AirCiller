# Maintenance candidate after 0.19.0

Work in progress, 5 November 2026. Base: `9123b9b`. No publication,
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
- Multidict #51: pending major-version compatibility and benefit review;
  do not include merely to clear Dependabot. Its dictionaries are used by
  aiohttp/yarl on the shared transport boundary.
- setup-node #43: pending current action-input/runtime review. CI-only;
  no Apple TV test is justified by this action alone.
- Final candidate: focused regressions during iteration, then the complete
  `Scripts/check.sh` strict gate once. Any later performance change requires
  a separate selection of affected cases before implementation.

## Sources

- https://github.com/certifi/python-certifi/compare/2026.10.19...2026.10.23
- https://github.com/aio-libs/multidict/releases/tag/v7.2.1
- https://github.com/actions/setup-node/releases/tag/v7.0.0

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

## Performance investigation

Pending bounded measurement. Existing preparation evidence remains in
`LOCAL_LIBRARY_PERFORMANCE_REVIEW.md`. No new speedup is claimed.

# GitHub maintenance, October 2026

Baseline: main `496decfd72efbe5b42373195a119cef8a801ead0`, after 0.17.0.
This audit does not publish a new application or replace an installed copy.

## Corrections

- The distribution diagnostic now verifies Apple's Developer ID Application
  certificate requirement. A local signing certificate is no longer reported as
  Developer ID. Hardened Runtime detection reads the CodeDirectory flags, not
  an arbitrary occurrence of `runtime` in a path. Six simulated cases cover
  ad hoc, local, valid and invalid signatures, mixed flags and failed metadata
  reads. The regression fails against the previous diagnostic.
- urllib3 is updated from 2.7.0 to 2.8.0 with the pinned lock generator. Only its
  version and hashes change in the lock. The upstream release fixes HTTPS proxy
  TLS handling and HTTP response parsing issues. This is an unreleased dependency
  change; published 0.17.0 assets are unchanged.
- The PR template follows the existing documentation-only validation policy and
  distinguishes receiver state, digital capture and physical observation.
  Third-party notices identify the license of the bundled FFmpeg build.
- About links to What's New and GitHub are scheduled for the next planned
  release. They are not implemented by this audit.

## Repository state

Sixteen merged branches were removed after checking that each tree exactly
matched its merge commit, that the merge was an ancestor of main, and that no
open PR used the branch. History and tags remain intact. The native-design
prototype and Shortcuts development branch retain unique work and were kept.

Dependency PRs #20 and #21 failed because they changed requirements.in without
regenerating requirements.lock. The urllib3 change is incorporated in this
maintenance work. Protobuf 7 is deferred: pyatv's generated control messages
target 6.31.1, and no concrete need for this major update was established.
This is not a finding of incompatibility. A future update needs a regenerated
lock, serialization checks and receiver-control validation.

Dependency alerts, secret scanning and push protection are enabled. Both alert
lists were empty when checked; that is not proof that every dependency is free
of vulnerabilities. Private vulnerability reporting remains enabled.

Main still requires the strict `build-and-test` check and disallows force pushes
and deletion. Actions retains read-only default token permissions. Full CI is
retained: PR, merged-main and release-tag runs establish different revision
boundaries. No path filter, skipped gate or retry was added to hide failures.
Documentation-only CI could be optimized later with a tested change classifier;
that coverage equivalence has not been established here.

## Checks and distribution

- The full local `Scripts/check.sh` gate passed with strict Swift 6,
  warnings-as-errors, reproducible lock verification and the new regressions.
- The built app passed its signature-structure and bundled-resource checks.
  Its logical size is 163,566,030 bytes, below the 165,000,000-byte budget.
- Public-content checks passed. Ninety-one relative document targets existed;
  the reviewed external links resolved successfully.
- All 23 published release bodies match their maintained versioned notes, and
  their tags exist locally. Older short note attachments were preserved with
  their historical signed feeds; they were not silently replaced.
- The latest public feed matches the previously verified 0.17.0 download.
  Ed25519 verification of the feed, full archive and delta passed using the
  installed app's public key. All four asset sizes and SHA-256 digests match
  GitHub's current release metadata.
- The older Python and FFmpeg assets hosted under 0.10.3 remain available and
  are retained for existing installations and reproducible builds.

No receiver playback or physical-output claim is made for the dependency change.
Before distributing it, complete the applicable engine-update playback checks
on both routes and the normal release gates. The installed app remains 0.17.0.

## References

- [urllib3 2.8.0 upstream changes](https://github.com/urllib3/urllib3/releases/tag/2.8.0)
- [urllib3 proposal](https://github.com/carlosciller/AirCiller/pull/20)
- [Deferred protobuf proposal](https://github.com/carlosciller/AirCiller/pull/21)
- [Released 0.17.0 verification](RELEASE_0.17.0.md)
- [Distribution procedure](../DISTRIBUTION.md#release-procedure)

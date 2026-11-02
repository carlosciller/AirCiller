# AirCiller 0.19.0 release record

Published: version 0.19.0, build 74, on 2 November 2026.
[Release](https://github.com/carlosciller/AirCiller/releases/tag/v0.19.0).
Installation was not authorized or performed; the daily app remains 0.18.4.

## Scope and validation selection

The [local-library goal](LOCAL_LIBRARY_IMPROVEMENTS.md) implements Continue Season,
manual explicit-chapter skips, reversible episode display names and playback
information that separates source, completed preparation and receiver state.
The [versioned notes](../Distribution/ReleaseNotes/0.19.0.md) describe their usage
and limits. No codec, engine, original-media or private-service change is included.

Retain the completed [season-action](SEASON_CONTINUATION.md) and
[chapter-skip](CHAPTER_SKIPS.md) local/native and HLS receiver/captured checks.
Both policy sources retain their recorded SHA-256 hashes. The later information
and name changes do not change selection identity, resume values, seek mapping,
AirPlay commands, either packager, the server/helper or bundled runtimes.
The prior direct route's compatible resume/seek and the 0.18.4 Stop/replay/close
evidence remain applicable at those unchanged boundaries. Reuse is not a new
HDR, codec, OCR, long-pause or whole-movie test.

The [episode editor](EPISODE_PRESENTATION.md) passed native Save/Cancel/Reset,
invalid-name recovery, Undo/Redo and restart persistence, with original names
and saved progress retained. The [information view](PLAYBACK_INFORMATION.md)
passed English/dark and Spanish/light wrapping, disclosure and scrolling checks.
The full native pointer/VoiceOver/older-macOS matrix is not claimed.

The release adds only version/build, versioned update notes and public
documentation to that accepted code. Required distribution gate: final ad hoc
strict check, actual bundle/signature/size audit, archive and signed feed,
reviewed PR/main/tag CI and published-byte/signature verification. No additional
Apple TV session is selected for these metadata changes.

Performance and Aether reviews are conditional decisions, not new shipping
speedups or spatial-audio features. See the [preparation review](LOCAL_LIBRARY_PERFORMANCE_REVIEW.md)
and [component review](AETHER_COMPONENT_REVIEW.md).

## Distribution evidence

- The final ad hoc release gate passed after versioning and notes were complete:
  `.build/release-0.19.0-check.log`, ending with `AirCiller local checks: OK`.
  It includes the strict Swift 6 build, warnings-as-errors, runtime/package and
  signature checks. Its accepted app was packaged without another build.
- Signed app size: 146,122,396 logical bytes, below 165,000,000. The signature
  structure is valid; Python and FFmpeg tools are bundled. The distribution
  audit reports only the four existing public ad hoc limitations: no Developer
  ID, Hardened Runtime, notarization ticket or Gatekeeper acceptance. This is
  not a notarized release.
- Accepted executable SHA-256:
  `40c997fbfcb33e3031ea04e26b126196aa00b179b0a62a13753f24dabdf2582f`.
- ZIP: `AirCiller-0.19.0-74.zip`, 59,302,377 bytes; SHA-256:
  `3f12c553299f529aabb01a4450396f3ee211ce32f234e7c209dafc069c4a5952`.
- Sparkle generated and signed the appcast and five deltas, from builds 69-73.
  The local full archive, all deltas and feed verify with the existing key; its
  public value matches the accepted app. The generator's ad hoc identity
  mismatch warnings were checked against both apps' identifier/signing flags;
  no signing policy or protection was changed. Historical public assets were
  not overwritten. The previous local feed was retained before generation.

## Exact-commit CI and publication

- [PR #53](https://github.com/carlosciller/AirCiller/pull/53) passed
  [full CI](https://github.com/carlosciller/AirCiller/actions/runs/41447962465)
  for head `fd5dd69123f1cb7433eb8d9eaab5eac7ba39314b`.
- It merged as `99ddd45e758bf8b17486f202e26103b4b8473e22`; its Git tree is identical
  to the reviewed PR tree (`ad3a2bf0c5e0085cd9ed778d74e9b3a961a410df`).
  [Main CI](https://github.com/carlosciller/AirCiller/actions/runs/41449776636)
  passed in reuse mode, linking that full-check evidence.
- Tag `v0.19.0` points to the same merged commit. Its separate
  [tag CI](https://github.com/carlosciller/AirCiller/actions/runs/41449920670)
  passed in reuse mode with identical full-check inputs. No test or CI
  requirement was weakened or skipped manually.
- All eight assets were uploaded to a draft first; names and sizes were checked
  before publication. The release was published at 13:06:48 UTC and selected as
  latest. A subsequent status query used an unsupported CLI field; querying the
  supported fields and the latest-release endpoint confirmed actual publication.
  That query error did not cause a second upload or replacement.
- Unauthenticated public downloads of the feed, full ZIP, all deltas and notes
  match the reviewed local bytes. Redirects remain HTTPS and on the approved
  GitHub asset hosts. Feed and every enclosure signature verify; the embedded
  app key matches. The latest-release feed returns the same accepted appcast.
- The GitHub Release body and downloaded notes match the reviewed versioned
  notes. The extracted public app reports 0.19.0 (74), has the accepted executable
  hash and passes deep strict signature verification. Its Sparkle framework
  inventory, including symlinks and signed nested code, matches the pinned
  framework exactly.

Private records are retained in `.build/release-0.19.0-verification`, including
CI logs, distribution audit, signed-feed generation, public hashes and signatures.
No native updater installation or daily-app replacement was performed. The
installed executable remains
`7468f56c611c0f9293c4c19f978d226d202a92414f3f22494a06c4bf41754466`.
No original movie, daily library or private-service deployment was modified.

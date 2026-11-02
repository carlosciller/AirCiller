# AirCiller 0.19.0 release record

Version 0.19.0, build 74. Publication authorized on 2 November 2026.
Installation is not part of this authorization; preserve the daily app.
Packaging, exact-commit CI and public-download verification remain pending.

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

Pending. Public ad hoc signing is not Developer ID or notarization. Required
signature-structure, runtime and size checks must still pass.

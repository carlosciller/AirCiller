# Bitmap subtitle boundary review

## Validation selection

Base: `a475fcd92294c7054e75473d2e8b825b11f15446` (0.19.1 maintenance).
Scope: local PGS/VobSub completion and OCR-cache reuse, inspired by upstream
AetherEngine 7.55/7.59 subtitle failures. AirCiller prepares the entire selected
track before serving complete VOD; it has no receiver-position-driven OCR window.
An upstream defect is not evidence of an AirCiller defect.

Check terminal bitmap intervals, repeated selections, duration-dependent cache
identity, and backward access to already finalized WebVTT segments. Use synthetic
inputs and the existing bitmap timeline and HLS subtitle preparation tests, then
the complete strict local gate once for the final candidate. Do not upgrade
engines or change either video packager.

If bitmap timing changes, both subtitle consumers require local checks; fresh
Apple TV output evidence for the affected terminal-cue case remains a separate
acceptance item. Unchanged transport, HDR codecs, long pauses and unrelated
audio modes do not require a new campaign. No publication or installation is
authorized by this review.

## Findings and correction

The synthetic regression reproduced a terminal bitmap starting at 98 seconds
in a 100-second movie ending at 103 seconds. The old fallback used the greater
of the movie duration and five seconds after the last bitmap. A clearing event
after the movie could also retain an overlong interval.

Full-track grouping now bounds every interval by the supplied movie duration
and discards intervals entirely beyond it. An earlier explicit clear is retained.
Frame-limited diagnostic extraction keeps its existing five-second fallback;
it does not populate the production cache. Invalid movie durations are rejected
before extraction or cache lookup.

Embedded PGS/VobSub cache identities previously omitted the supplied duration,
unlike external subtitle identities. This could reuse a final interval prepared
for a different duration, for example across container and finalized timelines.
Both now include duration. Cache policy v3 prevents reuse of old overlong results.
This means a previously cached bitmap track requires recognition once after
adoption; normal bounded pruning retains ownership of obsolete entries. No
ordinary cache was deleted during this review.

The repeated-selection test seeds an isolated cache and uses an intentionally
undecodable source. Both PGS and VobSub selections return the same cached text
twice without decoding. The ordinary track editor already disables Apply when
its draft is unchanged. Remote commands can still trigger re-preparation, but
that is distinct from rerunning OCR on a valid cache hit.

Backward seeking does not restart bitmap extraction: prepared subtitles already
cover the whole movie. Existing HLS regressions verify complete cue coverage,
including fragments shared across segment boundaries and explicit in-cue
timestamps. Those tests check packaged data, not receiver display timing.

## Validation evidence

- Before the behavioral fix, the new terminal-bitmap regression failed with
  `Failure.terminalBitmap`.
- Focused strict Swift tests passed after the fix: terminal bounds, duration
  identity, repeated PGS/VobSub cache hits, invalid durations, external subtitle
  validation and existing transport-clock/language cases.
- The first full-gate attempt stopped before application tests because the
  host Python had moved to 3.13.16. The retry explicitly selects the existing
  pinned engine's Python 3.13.15. The lock and runtime stay unchanged.
  Node 24.19.0 was prepared locally from its official archive and verified
  against the published SHA-256; no system Node or app dependency changed.
- All executable regressions and opt-in tool compilation passed. The publication
  wording check then rejected one phrase in this report. After correcting that
  prose only, the unchanged remainder of `check.sh` was executed from
  `check_publication.sh` through its final bundle assertions. No successful test
  or build was repeated. The completion log ends with `AirCiller local checks: OK`.
- Strict Swift 6 compilation, bundle inventory and signature verification passed.
  The development app is 146,117,835 logical bytes, within the 165 MB budget.
  Environment: macOS 27.2 (26B123), Apple Swift 6.4.2, Command Line Tools selected.
  `xcodebuild -version` is unavailable with that selection; the build uses swiftc.
- Candidate source SHA-256:
  `1aa553f1b8286056b295255da694bec6b70d47865efc159d401817a4b59121c2`;
  bitmap regression source:
  `6adea6a3c24c85c9aac1267bf83fcfc2a438551fae11aa61267e910501a34639`.
  Private logs: `.build/subtitle-boundary-check.log`,
  `.build/subtitle-boundary-check-pinned.log` and
  `.build/subtitle-boundary-check-completion.log`.
- Fresh terminal-cue output on Apple TV remains unverified. Availability was
  requested; no receiver, camera or microphone was opened. No release, installed
  app replacement, dependency update or private-service deployment occurred.

## Performance follow-ups, not part of this correction

1. Measure bitmap preparation by extraction, PNG I/O, recognition and cache
   lookup. Currently all frames are extracted before recognition starts, with
   up to four recognition tasks. A bounded producer/consumer pipeline or reuse
   of non-adjacent identical bitmaps could save work, but must preserve exact
   timing, local cancellation, memory bounds and complete VOD before playback.
2. Evaluate a bounded direct-MP4 preparation cache for repeated playback with
   identical inputs/settings. The direct route currently remuxes on each start;
   HLS already has a prepared-media cache. Audio/subtitle/delay changes must
   invalidate appropriately. Large-file disk cost is part of the decision.
3. Investigate Matroska attachment reads only with an affected anime/remote
   source. AetherEngine 7.55 introduces a patched demuxer option to skip them;
   this is not evidence of the same bottleneck in our pinned FFmpeg. Do not
   silently drop subtitle fonts or replace the bundled engine.

These are hypotheses, not measured AirCiller speedups. Existing warm-HLS and
analysis-contention measurements remain in the startup roadmap; they should
not be rerun without a changed alternative or new failure.

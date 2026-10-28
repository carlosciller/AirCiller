# Roadmap

AirCiller should stay quick to open and dependable through a whole movie.
This is a priority list, not a release schedule. Shipped features belong in the
[release notes](CHANGELOG.md); validation belongs in [Testing](TESTING.md).

## Shipped: 0.18.1 maintenance, 0.18.0 reliability and private control

The [October review](Docs/REVIEW_2026_10.md) owns the findings and acceptance ledger.
Its selected fixes are implemented and validated: cancelled direct startup,
sample-table-based direct HDR extraction, fresh receiver state, playlist admission
and selection, credential redirects, safe local installation and private-control
retry handling. The final strict gate, directed native checks, both video routes
and Stop/replay checks passed with the limits recorded there. Version 0.18.0 is
published and installed; its public download, signatures and native Sparkle
update passed. The private service corrections were separately deployed and
checked through the connected tools. [Release record](Docs/RELEASE_0.18.0.md).

The identified certifi and multidict advisories were addressed with targeted locked
updates. The separate [build-time pip correction](Docs/BUILD_PIP_MAINTENANCE.md)
uses a verified installer and excludes unused installers from app bundles.
Version 0.18.1 is published and installed through Sparkle. PR, main and tag CI
passed; the published archive matched the accepted local package. Existing
playback evidence remains applicable because playback inputs did not change.

## Faster playback startup

**Completed: private-library cache and demand-analysis baseline.**

Three complete movies, three empty/warm pairs each, have equivalent served bytes.
Warm HLS preparation medians are 2.279 s, 1.918 s and 0.566 s. A link-API
experiment did not show a worthwhile reliable saving; no production optimization
was adopted. The ordinary 16 GiB cache cannot retain the 20.92 GB first sample;
its experimental warm result used an isolated 32 GiB limit. See the
[measurement and decision record](Docs/LIBRARY_STARTUP_MEASUREMENT.md), including
CPU, sampled RSS, the corrected wrapper and measurement limits.

**Completed: paired direct-route demand-analysis experiment.** The corrected
12-sample campaign found a 3.964 to 10.439 s preparation penalty in all three
pairs for one large HDR movie, with byte-identical output. A smaller HDR episode
showed no consistent penalty. An initial biased harness run is retained and
excluded from performance conclusions. See the
[direct-demand record](Docs/DIRECT_DEMAND_MEASUREMENT.md).

**Validated local candidate: cancel and join unfinished analysis before direct preparation.**
Completed profiles are retained; diagnostics distinguish estimates from measured
peaks. The candidate also closes analysis pipes on cancellation and retains a
retirement barrier for immediate retries. The paired prototype measurement found
6.729-10.206 s less preparation time for the large HDR movie, with identical
output bytes. This applies only when analysis is still running at Play, and is
not a first-picture measurement. Strict local checks, directed digital output on
both routes, cancellation, Stop/replay and native diagnostic text checks passed.
See the [candidate review](Docs/REVIEW_2026_10_28.md) for scope and evidence limits.
It is not published or installed.

1. Retain the completed preparation baseline and its raw samples. Refresh only
   for a changed hypothesis or relevant production input; historical subtitle
   output is not byte-equivalent after the seek repair.
2. Review this candidate for the separate publication phase before another optimization. Keep
   integrity checks, finalized VOD and original audio/video quality. Profile
   individual cache operations only for a
   specific alternative; the link-API comparison provides no basis for a rewrite.
3. Return to transport measurements only with a specific new hypothesis. The
   recorded 3.31 s accepted-to-playing interval is not an established removable
   delay. Capture added about 1.28 s in one matched campaign; it is not a universal
   correction. The maintainer reports Wi-Fi 6 on the receiver; no settings change
   or new network tour is required. Continuous audiovisual onset remains
   unverified where capture had gaps. Do not repeat unchanged measurement runs.

The [current measurement record](Docs/STARTUP_MEASUREMENT_2026_10.md) separates
fresh local/live observations from historical evidence and measurement gaps.
The first optimization shipped in 0.13.0; its
[historical record](Docs/STARTUP_OPTIMIZATION.md) is not the current task list.

The maintainer readiness checkpoint is complete. The current review is authorized
to measure and implement justified small improvements. A deeper engine or
packager redesign is a separately scoped follow-up: notify the maintainer before
it starts so they can select the requested model and effort. Do not silently
switch models. Keep preparation/implementation separate from tests/publication.

Preserve complete VOD, duration, seeking, original media, HDR/Dolby Vision and
selectable subtitles. Change at most one packager per delivery. Do not trade
these invariants for progressive startup or claim newer libraries are faster
without measurement. Include external storage and bitrate peaks only in an
explicitly scoped follow-up; they remain unmeasured otherwise.

## Next small reliability improvement

Preserve one bounded local recovery snapshot before resetting malformed library
JSON. Decide how the user can inspect or restore it, test repeated corruption and
storage limits, and keep media originals untouched. The current reset behavior
is tested and unchanged; this is a data-protection improvement, not evidence of
a new corruption incident. Keep it separate from the validated startup candidate.

## Compatibility when a real collection needs it

- **Lossless audio:** extend PCM/LPCM precision, rates and layouts only with
  preservation tests and representative samples. TrueHD 7.1 needs a valid
  playback-length source for receiver coverage; 16-bit TrueHD remains unverified.
  FLAC channel-mask overrides must not silently relabel speakers.
  [Audio scope](Docs/AUDIO_EXPANSION.md) and [FLAC limits](Docs/FLAC_AUDIO.md).
- **Subtitles:** investigate TTML/IMSC1, DVB or XSUB only with useful examples.
  OCR stays local and selectable. Specialized in-cue WebVTT timestamps remain
  unverified after seeking; ordinary text cues have the 0.17.3 repair.
  [Seek record](Docs/HLS_SUBTITLE_SEEK.md).

TS/MTS/M2TS, supported FLAC soundtracks, PGS and VobSub are already available.
Do not reopen them as new features. [Current compatibility](COMPATIBILITY.md).

<a id="deferred-apple-shortcuts"></a>

## Parked or blocked

- **Private-control expansion:** opening and closing the installed app with the
  Mac awake and screen locked passed on 23 October through the connected MCP.
  The reviewed service corrections are now deployed. Bounded/paginated
  library search and a separately maintained service runtime are follow-ups; no generic system-control
  tools, remote unlock or media upload are planned.
- **DTS-HD MA lossless:** damaged extensions can decode successfully while
  changing samples. Resume only with a decoder guarantee or full qualification
  and an independent reference. No silent DTS-core fallback or promised DTS:X
  object preservation. [Investigation](Docs/AUDIO_EXPANSION.md).
- **AV1/VP9, MPEG-2 and DCP:** no current demonstrated need for the maintainer's
  third-generation Apple TV 4K workflow. No video transcoder is planned.
- **Apple Shortcuts:** public ad hoc registration failed on the tested Mac.
  Resume after the signing/distribution decision and remaining handoff checks.
  [Shortcuts record](Docs/SHORTCUTS.md).
- **iPhone title/artwork:** remote controls work; metadata on the Apple TV-owned
  Lock Screen card is not reliable. Defer further work until it has clear value.
- **Developer ID and notarization:** blocked until Apple Developer Program
  membership is available. Sparkle signatures do not replace notarization.

## Maintenance rules

- Keep engines pinned and bundled. Update for a concrete fix or security need,
  regenerate dependency locks and select checks by the affected boundary.
- zeroconf PR #30 is merged with a separate [lock and discovery review](Docs/ZEROCONF_MAINTENANCE.md);
  it is included in 0.18.1. Keep protobuf 6.33.6 until
  a major update has a concrete benefit and serialization/control evidence.
- Retain the 165 MB logical bundle budget. Trim only with measured savings and
  applicable checks; do not remove runtime files just to lower the number.
- Use [risk-based testing](TESTING.md#choose-checks-from-the-change), not the whole
  receiver catalogue for every release. Publication and native updating retain
  their separate [distribution gates](DISTRIBUTION.md).

No analytics, cloud library, background indexing or silent conversion. The
explicitly provisioned private-control relay/lifecycle service is the only
permanent-service exception; it carries commands and necessary metadata, not
media. Preserve originals and keep credentials/private media out of Git.

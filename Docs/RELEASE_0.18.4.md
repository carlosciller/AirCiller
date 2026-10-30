# AirCiller 0.18.4 candidate

Prepared version: 0.18.4, build 73. Not merged, tagged, published or installed.

## Scope and validation selection

- Optional fallback subtitle language from the [product review](NUVIO_PRODUCT_REVIEW.md).
  Retain its native English/Spanish Settings checks and selection/coordinator
  regressions: those inputs are unchanged.
- Shared AirPlay controller retirement ordering. Before replacement, request Stop,
  wait asynchronously for the actual previous process to exit, and clear its
  references. Stop or another start invalidates a waiting replacement. The existing
  two-second graceful shutdown and termination escalation remain unchanged.
- Neither packager, HTTP server, helper Python, dependency lock nor bundled runtime
  changes. Check Stop/replay on both routes; no new codec, OCR, long-pause or cache
  matrix is needed. Earlier audiovisual checks remain evidence only for their
  recorded inputs and intervals.

## Investigation

The original native direct-MP4 Stop/replay timeout is retained in
`capture-run-nuvio-j46kxc9a`. Its capture exceeded the fixed limit and is not a
passing capture. Subsequent matched baseline/candidate coordinator runs both
replayed successfully. The historic OS log query returned no retained entries;
that absence does not establish what the receiver did during the failure.

A new process-level regression reproduced an independent ordering defect in the
previous controller: replacement readiness returned while its retired helper
was still running. The failing assertion is retained in
`.build/replay-retirement-before.log`. The fix removes this verified overlap;
it is not proof that the overlap caused the earlier receiver timeout.

## Completed checks

- The initial strict gate passed after versioning and is retained as
  `.build/release-0.18.4-local-check.log`. Final review then exposed a cancellation
  interaction introduced by the new asynchronous wait: the predecessor's deferred
  callback could invalidate the replacement while joining that predecessor.
  A separate regression failed with `CancellationError` before the guard and
  passed afterward (`replay-retirement-cancel-before.log` / `-after.log` in
  `.build`). Cancellation now stops only its own active helper when no replacement
  already owns retirement. An explicit Stop still invalidates the replacement.
- The final strict gate passed with that executable change, retained in
  `.build/release-0.18.4-final-check-2.log`. The preceding attempt in
  `release-0.18.4-final-check.log` stopped at the public-prose guard before the
  application build; its flagged comparison phrase was rewritten. No validation
  rule was changed, and neither earlier attempt substitutes for the final pass.
  The intermediate CI run `41079150056` was requested to stop because that
  candidate was superseded, not because its tests established an application fault.
- Real-process regressions cover exit-before-replacement, task cancellation,
  Stop invalidation, superseding a waiting start, repeated Stop, an empty prior
  session, and a retired start's delayed cancellation during replacement.
  Existing late-event and timeline tests remain in place.
- A single directed two-route batch passed after repairing the private check
  bundle's credential-service metadata. The previous attempt failed before
  playback because that copy omitted the required client-version field. No
  credential permission, ACL, service or application source was changed to
  repair the harness. Two earlier custom-harness compilation attempts also
  lacked existing test-source dependencies; their logs remain retained.
- Each route used the real current coordinator, a 60-second local fixture,
  compatible original E-AC-3 and an automatically selected embedded English
  subtitle through Spanish-to-English fallback. Direct video was copied from
  an HDR source; HLS used a generated SDR pattern. Stop/replay happened near
  second 37 on direct MP4 and second 10 on HLS. Both restarted, advanced for
  eight seconds and released their runtime and helper references after Stop.
- Exact approved Apple TV digital source only, with complete source-verified
  manifests and separate initial/replay observation windows:

| Route/window | Frames | Expected subtitle | Central motion | Non-silent digital audio |
| --- | ---: | ---: | ---: | ---: |
| Direct MP4 initial | 65 | 61 | 62 | 146/175 |
| Direct MP4 replay | 12 | 12 | 11 | 32/34 |
| HLS initial | 18 | 18 | 17 | 44/44 |
| HLS replay | 14 | 14 | 13 | 36/36 |

HLS also showed the generated pattern in 7 initial and 10 replay frames. Window
coverage, minimum cue/motion/audio counts and fixed capture limits were retained.
These establish sampled digital output, not physical HDR rendering, speakers,
Atmos, exact synchronization or whole-movie reliability. No timeout occurred in
this batch. The original isolated receiver timeout is still not root-caused;
the narrower process-overlap defect is reproduced and corrected.

Private batch: `.build/playback-checks/capture-run-replay-c6rmlri9`.
Unsuccessful first batch: `capture-run-replay-o_6g95m1` in the same parent.
The private harness, source identities and build/capture logs are retained in
`.build/replay-0.18.4-evidence` and `.build/ReplayRetirementCheck.swift`.
Disposable test media and auxiliary compiled payloads were pruned through the
existing guard; reports, frames and one existing recovery copy were preserved.
Test storage returned to 11.91 GiB without raising the 12 GiB admission limit.

The sampled check app compiled the current production sources with existing
playback-check isolation and a private entry point. Its executable SHA-256 was
`6676553f00e00cd885fc623f462ccb41629ca20167fe8ce099d1b03e7d5508a3`;
the controller source SHA-256 was
`df326b3097eb9b587478995c4100bbf64053ed5e04c644cd5fa8675ff5cb5df7`.
The private entry point is not shipped in the ordinary app.

The process regression covers the final cancellation guard. No additional
television batch was run. It only changes the callback of a cancelled pending
start. Both captured Stop actions happened after confirmed startup had returned,
outside that callback's lifetime; the replacement wait and both packagers,
helpers, runtimes, fixture tracks and control sequence are unchanged. Those
captured checks are retained with this explicit input comparison, not described
as fresh checks of the later binary. Final controller source SHA-256:
`39c11758d29329013b3a7618a3497f3efc2fdd9b8540ac52c7ccd2b953f9970b`.

## Prepared distribution and remaining steps

The accepted ordinary app is 146,017,017 logical bytes, within the 165,000,000-byte
budget. Deep strict signature verification passes. The audit retains the expected
public ad hoc limitations: no Developer ID, Hardened Runtime, notarization ticket
or Gatekeeper acceptance. This is not a notarized build.

- Ordinary executable SHA-256:
  `7468f56c611c0f9293c4c19f978d226d202a92414f3f22494a06c4bf41754466`.
- Local archive: `.build/releases/AirCiller-0.18.4-73.zip`.
- Archive SHA-256:
  `ebaa5fb4d08e0e882e3fcfe46569c30b0502e8f487b9fd6a2f8556f8a7f0e746`.
- Versioned notes and CHANGELOG describe the same two user-facing changes.
- Daily 0.18.3/build 72 executable and complete saved preferences remained
  byte-identical across QA. Its idle window was restored. No installed app,
  original movie or private connector deployment was modified.

PR CI must be accepted for its exact final commit before merge. Publication,
tag/main CI, Sparkle feed/archive signing, public-download verification and native
installation remain separate authorized steps under DISTRIBUTION.md. The existing
local archive is prepared, not published or offered by the updater. No further
Apple TV batch is needed merely to merge/version the unchanged accepted inputs.

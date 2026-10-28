# AirCiller 0.18.2 release record

Status: [published](https://github.com/carlosciller/AirCiller/releases/tag/v0.18.2)
on 28 October 2026, build 71. No installation or private-service deployment was
performed. The daily app remains 0.18.1, build 70.

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

## Publication verification

The final strict local release gate passed on `def2d294e3178e382863903690f6785ebfc18177`.
Its log is `.build/release-0.18.2-final-local-check.log`. The signed bundle is
145,836,476 logical bytes, below the 165,000,000-byte budget. The final rebuilt
bundle matches the previously packaged candidate file-for-file, including
permissions and symlinks. No second package or playback campaign was needed.

| Gate | Result and evidence |
| --- | --- |
| [PR #45](https://github.com/carlosciller/AirCiller/pull/45) | Merged; [full CI attempt 2](https://github.com/carlosciller/AirCiller/actions/runs/40731112315/attempts/2) passed on `def2d29` |
| Merged main | [CI passed](https://github.com/carlosciller/AirCiller/actions/runs/40735668280) on `20901a21e935a6a24e4ff7d94b610991ba22b210`; identical full-check evidence reused |
| v0.18.2 tag | [CI passed](https://github.com/carlosciller/AirCiller/actions/runs/40735778971) on the same commit, also using verified reuse |
| Public download | All feed enclosures downloaded without authentication over HTTPS and matched accepted local hashes and lengths |
| Sparkle | Downloaded feed, ZIP and all five deltas passed the pinned tool's EdDSA verification; account public key matches the accepted app's SUPublicEDKey |
| Extracted app | Deep strict signature verification passed; executable hash matches the accepted build |
| Update delta | The 70-to-71 delta reconstructs every file, symlink and file permission of the accepted bundle |
| Release notes | Downloaded Markdown and GitHub body match the reviewed versioned notes |
| Daily installation | Version/build and executable hash unchanged; no native installation is claimed |

The accepted source tree is `2793caba949b7502d6129af2c2be3e7c962233e7` on both
the reviewed branch and merged release commit. PR attempt 1 never obtained a
hosted macOS runner and ended without executing tests; the same commit was
retried after that explicit infrastructure failure. It is distinct from the
earlier checker failure below. No runner label or test threshold was changed.

SHA-256:

- Release ZIP: `b1972d127d3710aadc67bf3ab01a87f9f17eba93bedf4d4da4708e3c42a08f42`.
- Release executable: `341dc236a0bff871fada16cd5165bc59bd3f9705bfed0b610096dc859a3be315`.
- Unchanged daily executable: `045cea170ee54e8d192ec54b4e8c1b5f6ad31ba76218a628b04ab31f30e4726b`.

Public verification copies are under `.build/release-0.18.2-verification/public`.
The distribution audit reports valid signature structure and bundled engines.
Missing Developer ID, Hardened Runtime, notarization and Gatekeeper acceptance
are the existing public ad hoc policy limitations, not successful checks.

### CI cancellation-check repair

The first [PR CI run](https://github.com/carlosciller/AirCiller/actions/runs/40728253831)
failed in StreamDiagnosticsSmokeTest with LeakedProcessOrPipe, despite the local
gate passing. Publication stopped. Repeated local executions reproduced it:
the child had exited in under a millisecond, but a reader descriptor was still
open at the immediate assertion. A pinned kernel pipe identity confirmed that
Foundation can finish retiring a readability source after the async task returns.
Descriptor numbers alone are also unsafe once another resource reuses them.

The test now pins each pipe identity with a temporary duplicate, checks retirement
of the original descriptors, and keeps the existing three-second total bound
for process and reader cleanup. It fails closed if inspection is unavailable.
The duplicate anchors close at the end of each iteration. Production code,
timeouts and cancellation behavior are unchanged.

Two hundred local test executions passed, covering 600 real bundled FFprobe
cancellations. A separately compiled negative control removed the cleanup defer:
the corrected test failed after 3.000 seconds with both original readers still
open. This is a checker repair with a demonstrated failing control, not an
unchanged rerun or removal of the leak assertion. The first failed CI is retained.

## GitHub audit, 28 October

| Finding | Evidence and decision | Verification |
| --- | --- | --- |
| README mixed setup with advanced integration | Put requirements beside download, explain which ZIP to choose, separate compatibility and help, shorten private-control description | GitHub rendering checked at desktop and 390-pixel widths; icon, links and wrapping inspected |
| Feature template claimed there was no permanent service at all | Qualify ordinary playback versus separately configured private control | Compare PRIVACY and private-control guide |
| Bug template used an old version example | Ask for the actual About version and build | Template diff |
| Roadmap mixed completed campaigns and future work | Separate published, recovery next, evidence-triggered follow-ups and blocked work | Cross-check code and dated review; preserve existing anchor links |
| Dependency PR #44 fails; #43 passes | #44 changes requirements.in without the lock; #43 is setup-node major 7. Both stay separate from this release | Read diffs and CI; no tests weakened or majors merged |
| Recent release prose | 0.18.1 is already concise; retain it. Group 0.18.0's existing facts for readability without changing signed assets | Compare public prose with original versioned notes |
| Private data and oversized history objects | Scan all 1,283 reachable blobs (20.3 MB total) for private-key/token patterns and personal paths; no secret match. Path matches are checker regexes. No blob exceeds 5 MB | Pattern scan is bounded evidence, not proof that every possible secret is absent |
| Licensing, privacy and attribution | GPL-3.0, original artwork, dependency notices, local OCR, optional metadata relay and Codex attribution are documented | Retain notices and package licensing checks |

The six primary external links checked returned HTTP 200; all 235 relative
Markdown targets existed. The compatibility introduction now identifies 0.18.2
and explicitly says format support is unchanged. The description is shorter and
user-facing; the existing latest-release homepage and relevant topics are kept.
Recent 0.17.1, 0.17.2, 0.17.3 and 0.18.1 release prose was already specific and
was retained. The 0.18.0 GitHub body was grouped by topic, with an editorial-date
note; its assets retain their original update dates. All 28 preceding public
releases retain ZIP assets, including the required v0.10.3 engine archives.

There were no open issues, Dependabot security alerts or secret-scanning alerts
at audit time. Closed issue #32 remains closed; the related server repair is
already in 0.17.3. These checks do not establish absence of every possible bug or
vulnerability. PR #43 and #44 remain pending independent dependency reviews.

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

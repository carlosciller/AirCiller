# Explicit chapter skips

Delivery 2 of the local-library goal. Manual action only; no automatic skipping,
fingerprinting, online markers, file mutation or assumed intro length.

## Contract and selected checks

Show Skip Intro or Skip Recap only inside one explicitly named, finite chapter
with a valid original-movie interval. Reject overlapping/nested or duplicate
editions, generic Chapter N labels, combined/unknown labels, an end beyond the
movie, or a skip to the whole-file end. Preserve the chapter's exact endpoint;
there is no fixed 90-second jump or arbitrary duration truncation. The help text
names the file marker and destination. File labels are evidence supplied by the
file, not proof that the content was accurately labeled by its author.

Supported names include Intro/Introduction, Opening/Opening Credits/Opening Theme,
OP/OP1/OP2, Introducción/Cabecera/Apertura, Recap/Previously/Previously On,
Resumen/Anteriormente/En episodios anteriores/Recapitulación and explicit Japanese
opening/recap labels. Case, whitespace, accents, width and a numeric chapter prefix
are normalized. Substring matches do not qualify. Unrecognized metadata remains
available through the existing chapter controls; an absent action is not a probe
failure. Files with generic chapters have no trustworthy skip interval.

The coordinator revalidates the marker on every explicit action, rejects pending
work through existing seek availability, and maps its source-clock endpoint to
the existing presentation clock. No new seeking protocol, packager or renderer.
Local selection/coordinator regressions and actual native UI are required. A
directed seek observation covers the new control; do not repeat unrelated codecs,
OCR or long-pause checks. Keep receiver/captured and physical evidence distinct.

## Validation, 2 November 2026

The complete strict local gate passed (`.build/chapter-skip-full-check.log`),
including selection and actual-coordinator regressions. The native isolated view
showed Skip Intro at 00:06, Skip Recap after the action reached 00:20, then no
skip at the generic chapter starting at 00:40. English/dark and Spanish/light
were checked without changing the system appearance or daily preferences.

A bounded metadata-only review of the 17 entries in the saved daily queue
successfully probed all 17; 16 had chapters, but none qualified under the explicit
label policy. That sample does not establish that the entire movie collection
lacks markers. Generic chapter boundaries were not turned into assumed intros.
Private paths and chapter metadata remain in ignored local reports.

One authorized HLS check used a synthetic 60-second H.264/E-AC-3 stereo clip,
selectable English subtitles, Intro 0–15 and Recap 15–30. The real probe read the
markers. Each action required a fresh receiver position: 15 and 30 seconds.
After each confirmation, the eight-second sampled windows passed separately:

| Action | Frames | Expected subtitle | Moving frames | Pattern frames | Non-silent audio measurements |
| --- | ---: | ---: | ---: | ---: | ---: |
| Intro | 14 | 13 | 14 | 6 | 35/36 |
| Recap | 13 | 13 | 13 | 6 | 34/34 |

The generic chapter offered no action. Stop released the runtime and the approved
digital capture completed; no other capture source was opened. Reports are in
`.build/playback-checks/capture-run-chapter-36d2z8dy`. The run retains input,
candidate, policy, harness and evaluator identities. The storage guard removed
its generated clip and disposable build, not reports or recovery copies.

This establishes the sampled SDR HLS control behavior, not physical speakers,
HDR rendering, every author's marker accuracy or every movie. The direct MP4
packager, HLS packager, existing seek protocol and timeline mapping are unchanged.
The new action uses that existing mapping; its non-identity case has a local
regression. Existing direct seek evidence is reused at that boundary, not claimed
as a new direct/HDR device run. Neither video route was rewritten.

The installed 0.18.4 executable remains SHA-256
`7468f56c611c0f9293c4c19f978d226d202a92414f3f22494a06c4bf41754466`.
No publication, installation, pairing or credential write occurred.

# Quality completion checkpoint

Scope: complete the five agreed quality blocks before reassessing the project.
Keep the installed app and original media unchanged. Publication and installation
are separate decisions. A score is a qualitative assessment, not a guarantee.

## Acceptance and current state

| Priority | Block | Acceptance | State |
| --- | --- | --- | --- |
| 1 | Preparation candidate | Preserve the passing local gate; scoped direct-cache and terminal bitmap checks on both affected consumers; inspect Settings in both languages | Complete local gate, English/Spanish layout and scoped digital receiver checks passed |
| 2 | Real-library preparation measurements | Representative episode, HDR film and bitmap source; separate cold/warm preparation from receiver startup; bounded private storage | Completed below; cold variability stated, no receiver-speed claim |
| 3 | Bitmap preparation efficiency | Measure repeated-image recognition before changing scheduling; preserve text, timing, cancellation and bounded memory | PNG change retained; additional scheduler/cache deferred after measuring a 1.98% repeated-image ceiling |
| 4 | Sofa controls | Reproduce redundant-command or rapid-change failures; scoped regressions and actual affected-control checks | No-op correction, complete local gate and scoped receiver controls pass; not a fresh iPhone connector deployment test |
| 5 | Useful format coverage | Inventory actual library gaps and avoidable conversion; implement only a justified, bounded candidate with reference comparison and receiver acceptance | Inventory and Aether decoder review complete; DTS-HD MA remains unsafe to widen without the missing guarantee |

## Research boundary

Aether's whole-engine experiment is closed as documented in
[the prototype decision](AETHER_PROTOTYPE_2026_11.md). The unexplained E-AC-3
160-sample difference remains unexplained; its investigation is closed.
Use individual ideas only where AirCiller has a measured bottleneck or reproduced
failure. AirPlay acceptance does not follow from another engine's local playback.

## Evidence reuse

Start from [preparation evidence](PREPARATION_REVIEW_2026_11.md) and
[subtitle boundary evidence](SUBTITLE_BOUNDARY_REVIEW_2026_11.md). Preserve their
candidate identities. Run focused regressions during changes and one final full
gate on the final code candidate. Do not repeat unchanged receiver scenarios.

## Current handoff

### Completion review

The five bounded blocks are complete: candidate acceptance, real measurements,
evidence-based bitmap optimization, reproduced control correction, and the useful
format qualification decision. Block 5 concludes with no safe expansion, not new
DTS-HD MA support. Publication and installation were not requested in this goal.

A read-only instrumented discovery later received five datagrams and found one
device, with no warnings and one private non-loopback interface. No network,
permission, credential or engine setting changed. Discovery was intermittent;
its underlying cause remains unknown. The fresh campaign then found the configured
receiver normally, without injecting an address or bypassing the runner check.

Scoped campaign: `.build/playback-checks/capture-run-quality-tey6tzx6/report.json`.
Check executable SHA-256:
`5e07bc10ae9eff4f0822ba8915ed76c7a98d297671ee6aeb3aff12610b5d38ff`.
All three direct cache cases (miss, hit, changed-subtitle miss) passed receiver
controls and sampled output assessment: expected cues in 29/27/24 frames,
motion in 24/22/26 frames and non-silent digital audio in 55/39/54 measurements.
No reported gaps in those assessed windows. Unchanged remote settings preserved
the session; pause, resume, seek destinations and cleanup passed. The isolated
cache was removed. Nothing was deployed to the private relay.

Terminal bitmap checks passed on direct MP4 and HLS: natural completion,
unchanged-setting no-op and cleanup. Offline visual review compared the retained
SUP rendering with direct frames 84/88/92 and HLS frames 28/32/34. The final cue
matches the source wording on both routes; curly apostrophes normalize to straight
apostrophes. HLS shows the cue at 59.200 seconds and no cue at the final 59.967-second
frame. Do not claim frame-accurate subtitle endpoints. Terminal windows contain
22/17 frames, 21/17 changed frames and 44/39 non-silent audio measurements.
`terminal-review.md` records the review separately; the original report is retained.
This proves sampled digital output, not physical HDR/Atmos, speakers or exact sync.

The campaign process exited zero and each receiver case confirmed cleanup.
The generated test media were pruned by the storage guard. Reports and sampled
evidence remain private. No installed app, original movie or daily preference was
replaced. No further unchanged playback batch is required for this goal.

Remaining product limitations: unexplained intermittent multicast discovery,
DTS-HD MA qualification, independent Aether timing discrepancy and release-stage
CI/signature/updater verification when publication is authorized. These are not
silently counted as fixed. A qualitative score is not proof of universal stability.

### Maintainer-use assessment

Qualitative assessment of this candidate for the maintainer's Mac-to-Apple-TV use:
**88/100**. This is an engineering judgment, not a standardized benchmark or a
rating of the unchanged installed version. Original-media preservation, scoped
receiver evidence, regression coverage and measured warm preparation are strong.
The remaining discovery uncertainty, unsupported lossless audio cases, imperfect
bitmap OCR and unperformed release gates prevent a perfect score. Aether remains
a source of specific testable ideas; replacing the engine has no demonstrated
benefit from the completed prototype investigation.

### Earlier continuation

Latest continuation supersedes the running-process notes below. The suffix of the
strict gate exited zero and ends with `AirCiller local checks: OK` in
`.build/quality-completion-check-final.log`. The executable tests from the first
pass remain applicable: only editorial prose changed before the suffix rerun.
Both auxiliary builds passed. No production executable input changed afterward.

The check bundle originally lacked this worktree's local signing configuration.
Its first readiness attempt failed the noninteractive credential check. The exact
existing credential service from the original project was verified against its
unchanged sources, copied into the generated check bundle and signed with the
existing identity. No credentials, Keychain permissions or installed app changed.
The resulting noninteractive credential check passed without a prompt.

The signed campaign at `.build/playback-checks/capture-run-quality-49_pmc8o`
passed exact-source digital-capture readiness but stopped at `deviceUnavailable`,
before movie playback. Isolated cache cleanup was confirmed. Generated fixture
movies were pruned by the storage guard; regenerate them before another campaign.
The earlier failed attempt remains at `capture-run-quality-5tlspx_s`.

Bounded discovery diagnosis: system Bonjour advertises the configured Apple TV
with matching identity; its approved digital source shows the receiver screensaver.
The bundled helper's multicast scan returns zero devices. A unicast scan to the
address resolved from that exact Bonjour identity returns one matching device,
exit zero and no stderr. A separate read-only pyatv/AsyncZeroconf discovery also
returned zero devices. This isolates an operational multicast-discovery failure,
not its underlying network/OS cause. It does not prove a playback failure or
authorize injecting a device into the runner to manufacture acceptance.
Next: investigate this boundary without changing network settings or credentials;
do not repeat the capture batch until readiness has materially changed.

Native Storage settings were inspected in the UI candidate in English and Spanish.
The changed cache explanation wraps without truncation, and the limit/clear
controls remain visible. Languages were launch arguments only; no system or daily
app language changed. No cache limit or clear control was activated. The UI
candidate was quit after inspection. This is scoped layout acceptance, not a
general accessibility or appearance campaign.

### Earlier checkpoint (superseded where noted above)

Latest continuation: the full strict gate (`77758`) completed executable tests
and stopped at the editorial check. Its log is
`.build/quality-completion-check.log`. Formulaic wording in the new reports was
corrected; `check_publication.sh` now passes. No executable inputs changed after
those tests. The remaining exact script suffix (publication, build and bundle
assertions, beginning at line 579) is running as unified-exec session `97576`,
log `.build/quality-completion-check-final.log`. Poll that handle before any new
build. Synthetic blocked-capture reports inside the earlier log are test fixtures,
not device attempts. Final app build and bundle acceptance still pending.

Prepared a 179 MiB private terminal-cue fixture directory at
`.build/quality-terminal-fixture-20261109`. Its PGS image is copied from an actual
source display, with synthetic starts at 0 and 58 seconds, clear at 40 and no
final clear. HDR video/audio copied from the retained 60-second fixture; SDR
video/tone are synthetic. Originals unchanged. Register/move these generated
files into the live campaign's guarded run before execution/cleanup.
New `terminalBitmap` runner profile and isolated direct-cache expectations pass
the deterministic plan tests. The new check app still needs compilation; no TV
capture has begun. Finish the ordinary gate before building auxiliary apps to
avoid shared build-resource races.

- Recovered branch `codex/subtitle-eof-cache-review`; existing work preserved.
- Confirmed remote track selection currently calls `applyTrackSettings()` even
  when requested IDs match. Inspect coordinator behavior before calling it a bug.
- Bitmap recognition currently schedules up to four groups concurrently; inspect
  grouping and real repeated-image frequency before adding OCR reuse.
- Requested current TV availability once; independent local work can continue.
- Next: select bounded real-library inputs, reproduce the control behavior and
  retain reports without accumulating prepared full-film copies.

### First local observations

Real-file metadata queries (current bundled ffprobe, three sequential reads per
input; OS cache not purged) took:

| Input | First read | Immediate repeats | Relevant tracks |
| --- | ---: | ---: | --- |
| 24-minute HDR episode, 2.90 GB | 30.47 ms | 11.94 / 10.80 ms | HEVC, E-AC-3 5.1, text |
| 97-minute HDR film, 10.37 GB | 15.40 ms | 12.62 / 13.39 ms | HEVC, AAC mono/stereo, VobSub |
| 116-minute SDR film, 7.20 GB | 15.83 ms | 12.82 / 11.95 ms | HEVC, FLAC mono 16-bit, PGS/text |

These are metadata-only queries, not full preparation or disk-cold claims. They
support focusing the next measurements on remux/cache and bitmap preparation.
Originals were read only; no prepared film copies were generated.

Remote inspection confirmed unchanged selections and offsets restarted preparation.
The candidate now compares complete track settings before applying them, retaining
the explicit reset to Original when an audio track is selected. An unchanged
request completes locally and cannot own cancellation of another operation.
Added coordinator/gateway regressions for active-session preservation, no-op
cancellation rejection, actual offset changes and explicit output-mode changes.

The first coordinator suite compiled successfully but failed later at the native
drag-writer check. It is not a full passing gate. A focused remote-settings entry
point is being checked separately; the normal suite still executes all tests.

The focused `Scripts/check_library_coordinator.sh --remote-settings-only` passed
with strict Swift 6 and warnings-as-errors. It runs the production dispatcher,
gateway and coordinator in a fresh isolated preferences domain without discovery
or real media. The regular entry point retains the new check and all existing UI
checks. Full final gate and scoped receiver checks remain pending.

The maintainer subsequently confirmed the Apple TV is free and on for this batch.
Use only its previously approved digital source. No receiver run has started yet.

### Actual-library format inventory

Read-only ffprobe inventory covered 31 discovered MKV/MP4/M2TS/AVI files under
Movies, excluding project/build/git directories; no probe failed. This is not an
inventory of cloud/offline media or every possible extension. Present audio:
AAC LC/HE-AAC, E-AC-3 (including Atmos), AC-3 mono, FLAC mono/stereo at 16/24-bit,
and ten DTS-HD MA 5.1 24-bit tracks. Subtitles: SRT, ASS, PGS and VobSub.
No TTML, DVB, XSUB, PCM or TrueHD track appeared in this bounded inventory.

The actual original-audio gap is DTS-HD MA. Keep its documented independent
decoder/reference qualification requirement; the presence of an alternate FLAC
track does not establish matching language or content. Do not add unrelated
formats or silently change tracks to claim completion. Next format decision:
assess a trustworthy reference for this existing gap, otherwise leave it explicitly
blocked and propose no speculative codec addition.

### Real preparation measurements

One bounded disabled/empty/warm direct preparation comparison on the 24-minute
HDR episode measured 2.790 / 2.171 / 0.0174 seconds. All three MP4 outputs have
SHA-256 `aeca192e343eb274f47aaba5833ff6187593e7d363d70d04f68c75286d2954ac`.
Source hash was unchanged. This uses the production command/cache/probe services
and a generated text track, not the entire coordinator, HDR injector, AVPlayer or
receiver. Evidence: `.build/performance/run.dwuizz3u/measurement.json`.

Full-track PGS preparation on the 116-minute film produced 658 cues in 43.603 s:
6.509 s extraction/grouping and 37.094 s recognition/write. Warm isolated cache:
0.001215 s with identical WebVTT, SHA-256
`bb62d9f5445bf0e8e19a025a824525699961917a22db72a2f53dc5969b20e9bc`.
Evidence: `.build/performance/run.s9mbnre0/measurement.json`. The first restricted
attempt failed creating a Vision pixel buffer; the authorized unrestricted local
retry passed. No alternate engine, camera, microphone or receiver was used.
Both harnesses are storage-guarded and remove generated media while keeping reports.

The 97-minute HDR film measured 14.096 s disabled, 32.610 s empty-cache admission,
and 0.1326 s warm. Outputs were byte-identical with SHA-256
`7b66faf3e681581b090e0a35fb4c8454628e783b5cf8378aa0d888fdf6dc878a`.
Evidence: `.build/performance/run.9hqpb2p9/measurement.json`. This single pass
shows substantial cold-run variability; it does not establish an admission cost
of 18 seconds or a universal speedup factor. Admission uses hard links, not a
second full-media copy. Report the measured warm reuse separately from cold I/O.

### Bitmap optimization decision

A separate full extraction of the same PGS track found 658 visible groups and
645 unique image/crop pairs: only 13 repeated recognitions (1.98%) are avoidable
by exact-image reuse. Evidence: `.build/performance/run.btig1rzd/measurement.json`.
This counts actual encoded images and bounds after adjacent grouping, not repeated
words. It does not prove recognition cost is uniform or promise a proportional
time saving. Do not add a new image-cache/scheduler for this small observed ceiling.
Retain the already measured lossless PNG optimization and whole-track cache.
Extraction/recognition overlap has at most the measured 6.509-second extraction
interval to hide on this file, before contention and synchronization costs; a
pipeline rewrite still needs a measured benefit.

Inspected Aether 7.62.0 `SubtitleImageOCR.appendRecognized` and its `Executor`:
it serializes admitted recognition with cancellation-aware waiters. It provides
no demonstrated faster whole-track batch than AirCiller's four tasks.
Its windowed readiness behavior is not a substitute for complete VOD. No OCR
concurrency or progressive packaging change is adopted.

### Format decision

Re-read the independent DTS evidence in `AUDIO_EXPANSION.md`: an extension-sync
mutation changes decoded samples without an error or the diagnostic strings.
Aether's `AudioBridge.swift` opens the same FFmpeg decoder family and explicitly
describes skipping some failing packets. That behavior is not the missing
lossless guarantee and must not be imported as a fix. No useful safe new-format
implementation is established for the present library. Keep DTS-HD MA lossless
blocked; eligibility and the pinned engine remain unchanged. Revisit
only with a decoder/bitstream guarantee covering those retained negative cases.

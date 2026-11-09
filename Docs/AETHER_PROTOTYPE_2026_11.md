# AetherEngine isolated prototype, 9 November 2026

## Decision and scope

**Closed investigation, 9 November 2026: do not adopt the whole engine.**
The prototype is retained as research, not accepted for shipping. The conditional
Apple TV comparison is not queued. No installed-app change or new playback run
was needed to reach this decision.

The closure review used the retained reports and packet hashes; no campaigns were
repeated. AAC (`run.267b823h`) passes exact packet and decoded-PCM
equality after experimental metadata corrections. E-AC-3 (`run._5pmbtl6`)
retains all 844 encoded packets, byte-for-byte and in order. The native macOS
reader emits 1,295,840 samples from both the Aether candidate and an independently
stream-copied MP4 reference, with identical decoded-byte hashes. The source's
FFmpeg decode emits 1,296,000: a difference of 160 samples, or 3.333 ms at 48 kHz.

That identifies the discrepancy as reproducible outside Aether's packager; it
does **not** isolate its exact cause to Apple's decoder. Both comparisons share
MP4 presentation edits and a native reader, and the MP4 reference itself fails
source-PCM equality. There is no accepted fidelity reference for declaring the
difference harmless. Earlier claims that the final-block duration was *the*
cause were premature: correcting it did not restore the samples.

The precise trimming mechanism remains unresolved. This is a closed product
decision with an unresolved technical observation, not a claim that the bug was
fixed or that E-AC-3 cannot work through AirPlay. Existing acceptance failures
remain unchanged; no synthetic offset, silence or transcoding was introduced.

### Why stop here

- No matched Play-to-picture performance gain has been established.
- No new maintainer-use capability has been validated through this whole-engine
  prototype on Apple TV. Local engine features are not automatically receiver
  features, and the existing AirPlay controller would still be required.
- The experiment already requires private upstream patches and metadata
  finalization. Their maintenance cost is real; integration savings are unproven.
- HDR/DV, selectable subtitles, seeking and session continuity have not passed
  receiver comparison for this candidate. Two SDR fixtures cannot establish
  replacement coverage for AirCiller's working routes.

Further decoder research would not change today's adoption decision even if
all 160 samples were explained. Therefore no additional media generation,
decoder probe, build or TV run is justified for this closure.

### Reopening criterion and next work

Reopen only for a named user-visible benefit that AirCiller lacks, with a bounded
component experiment and comparative evidence of value. An upstream fix may
reduce the investigation cost but does not itself justify whole-engine adoption.
The separate spatial-component research remains subject to its own output and
resource checks. The next AirCiller planning step is to prioritize its existing
stability, usability and measured-startup work; this closure does not start it.

Historical candidate details and failed experiments follow for traceability.

The maintainer authorized an isolated prototype and comparison, with the Apple TV
available, no installed-app replacement and no app installed on the receiver.
The local prototype is implemented. The first complete comparison exposes an
original-audio difference, so receiver testing has not started. It is not a
recommended replacement for AirCiller yet.

No production source, engine pin, packaging route, credential, daily setting or
private-control service was changed in this investigation. The earlier subtitle
and preparation changes on the branch are preserved, not attributed to Aether.

## Candidate

- AirCiller working branch: `codex/subtitle-eof-cache-review`, based on
  `a475fcd92294c7054e75473d2e8b825b11f15446`.
- AetherEngine 7.62.0: `a1d2cab8281cbf06f5f459b05dad4653ad12559f`.
- Full Aether session through its public API; native HLS, original compatible
  audio, native text-subtitle renditions. No optional traits enabled.
- FFmpegBuild 3.14.0, LibDovi 2.2.0 and SMBClient 0.3.1. Exact revisions and
  reproduction commands are in the [prototype README](../Prototypes/AetherComparison/README.md).
- Prototype executable target added only to the ignored dependency checkout.
  The engine implementation is unmodified. SwiftPM removed the unused optional
  LibTrueHD pin and updated the lock origin hash; this is recorded, not an
  unreported dependency upgrade.

## Observed local comparison

Fixture: 27 seconds, H.264 1280x720 at 24 fps, AAC at 48 kHz and one embedded SRT
cue. Explicit development fixture encoding is separate from both playback
engines. Source SHA-256:
`9c1798f63886c8c3deb445f1b28c9c343cbc1fe4f8514926020d842c6190f469`.
Record: `.build/performance/run.snowkflz/report.json` and `stream-parity.json`.

| Observation | AirCiller | Aether |
| --- | --- | --- |
| Decoded video frames | All 648 match source | All 648 match source |
| Ordered original AAC packets | All 1,267 retained | 1,266 retained |
| Remaining Aether audio packets | Reference | Exactly source packets 2 through 1,267 |
| Native subtitle representation | Existing HLS subtitle preparation | WebVTT rendition contains expected text |
| Complete VOD before receiver use | Existing validation | All fetched media playlists have ENDLIST |
| Source file | Unchanged | Unchanged |

The first AAC packet is absent from Aether's output. No other audio-packet payload
differs. `HLSSegmentProducer.swift` describes and implements dropping audio before
the first video anchor, including a negative-output-DTS rejection. That policy is
consistent with the observed missing prefix. A source-timestamp trace has not yet
proved the exact branch taken, and this comparison does not establish whether
the missing packet is only encoder priming or contains an audible sample. Do not
label it audible loss or harmless padding without that next observation.

The strict audio-parity gate remains failed. No test or production policy was
weakened to call the result equivalent.

## Follow-up: packet timing and E-AC-3

Two targeted local runs retain packet timestamps, skip-sample metadata and decoded
PCM statistics in `stream-parity.json`: AAC `run.y7lu_gwc` and E-AC-3
`run.1xh95i5b`. The comparison script now accepts an explicit fixture codec. Both
use the same unchanged hosts and engine pins. No receiver test was performed.

- AAC: the omitted packet has PTS -21 ms and explicitly declares 1,024 skip
  samples at 48 kHz. It is encoder priming, not 21 ms of intended presentation.
  Nevertheless, decoding without that packet changes the next frame: the first
  1,024 presented samples have RMS 0.102143 in the source versus 0.080884 in
  Aether. Both decoded outputs contain 1,296,384 samples. This establishes an
  initial decoded difference, not its audibility or the extent of later changes.
- E-AC-3: the omitted packet starts at -5 ms, spans 1,536 samples (32 ms), and
  declares only 256 skip samples. The remaining 1,280 samples (26.667 ms) belong
  to presentation. The source's first 1,024 presented samples have RMS 0.088379,
  so this is not simply an all-silent prefix. Aether starts with the next packet
  at +27 ms and retains 843 of 844 packets, exactly source packets 2 onward.
  Removing a whole packet that straddles the video anchor loses useful content.
- AirCiller retains every encoded packet in both fixtures. This is packet
  preservation, not proof of perfect priming/timestamp treatment: its output
  places the priming packet at zero without the source skip metadata, and its
  decoded length differs. That independent timing detail remains unvalidated.

All 648 decoded video frames match for both codecs and engines; the expected
native subtitle text remains present and source hashes remain unchanged. The
strict audio gate still fails. E-AC-3 therefore blocks the conditional receiver
comparison independently of how AAC priming is classified. No TV test would
resolve the already demonstrated local packet loss.

An initial restricted execution (`run.sqi6x3rb`) crashed in macOS renderer setup
before producing a session. A scoped retry with local renderer access produced
the reports above. This environment failure is retained separately from the
codec results. Generated media was cleaned by the storage guard; reports remain.

Next: investigate preserving decoder pre-roll and trimming presentation rather
than dropping the entire straddling packet in an isolated upstream experiment.
Do not adopt the engine or proceed to TV parity acceptance with this result.

## Opt-in pre-roll repair experiment

The maintainer authorized changes only in the isolated prototype. The pinned
checkout now has `preroll-experiment.patch`; earlier statements about unchanged
upstream code describe the preceding candidate. Production AirCiller sources
and the installed bundle remain untouched.

Preserving negative packets and enabling MP4 edit lists alone still lost the
first packet (`run.6t888c17`, AAC; `run.9brhssvh`, E-AC-3). Host tracing showed
E-AC-3 first reaching the audio gate at +27 ms (`run.95b13gyc`). Seeking to -1
second also failed (`run.yksyotfc`, `run.7u6ctqwe`). A fresh local-file demuxer
for the initial producer finally retained the pre-zero packet. The experiment
does not validate arbitrary source anchors, restarts, live or remote input.
Its environment flag is off by default and the normal build does not apply it.

Final records: AAC `run.3n505ple`; E-AC-3 `run.4co02mr4`.

| Check | AAC | E-AC-3 |
| --- | --- | --- |
| Exact ordered audio packets | 1,267 / 1,267 retained | 844 / 844 retained |
| Decoded video frames | 648 / 648 identical | 648 / 648 identical |
| Source and subtitle text | Preserved | Preserved |
| Source decoded samples | 1,296,384 | 1,296,000 |
| Experimental decoded samples | 1,296,400 | 1,296,384 |
| Exact PCM parity | FAIL | FAIL |

AAC requests 1,024 skipped samples in the source, but output signals 1,008,
matching rounded -21 ms instead of exact codec pre-roll. E-AC-3 retains the
first packet at -240 ticks (-5 ms), but lacks the source's 256-sample skip
instruction; source tail trimming is also not reflected in decoded length.
These are presentation differences despite byte-identical compressed audio.
Their audibility on Apple TV has not been tested or claimed.

The acceptance gate now requires exact decoded PCM equality as well as packet
equality. Five helper tests pass, including rejection of changed/truncated PCM.
The experimental host builds; upstream warnings remain. All campaign processes
exited and the storage guard cleaned generated media. No installed app change,
general app rebuild, receiver suite or pairing was performed.

**Partial repair, not accepted:** packet preservation is corrected for these
fixtures. Exact pre-roll and tail presentation in fragmented MP4 is still the
blocker. Do not relax the comparison, shift all audio blindly, or proceed to
receiver acceptance until presentation matches the source.

## Exact presentation-edit follow-up

`trim_metadata.py` modifies only the audio `elst` media-time and presentation
duration in a finalized local snapshot. It neither changes encoded packets nor
rewrites fragment timestamps, video tracks or subtitle resources. The initial
skip comes from source packet metadata; this bounded research implementation
decodes source frames to count presented samples for exact end trimming (no
encoding). That full decode is not proposed as production startup work.
The tool rejects incompatible timescales, multiple edits and unrelated offsets.
`AIRCILLER_EXACT_EDIT_PROBE=1` explicitly enables it alongside the pre-roll flag.

- AAC, final `run.267b823h`: media-time 1,008 corrected to 1,024 samples at
  48 kHz; presentation duration 27,008 ticks at a 1,000 Hz movie timescale.
  All 1,267 packets and all 1,296,384 decoded samples match the original exactly.
  All 648 video frames match, subtitle text is retained and the source is unchanged.
  Earlier `run.m74y4jhg` passed the head-only correction before duration was added.
- E-AC-3, `run.chawx9_b`: media-time 240 corrected to 256 samples and presentation
  duration set to exactly 27 seconds. All 844 compressed packets are retained,
  but FFmpeg still emits 1,296,384 samples instead of the source's 1,296,000.
  `run.90e76_83` records the prior head-only attempt.
- The official [FFmpeg 9.0.1 MOV reader](https://github.com/FFmpeg/FFmpeg/blob/n9.0.1/libavformat/mov.c)
  disables advanced edit-list handling for fragmented MP4 and its simpler
  initial-padding branch specifically handles AAC. This explains why matching
  metadata alone cannot validate E-AC-3 through that reader; it does not establish
  Apple receiver behavior.
- A separate current-API `AVAssetReader` helper, `ReadAudio.swift`, was built with
  Swift 6 strict concurrency and warnings-as-errors. It reads only the finalized
  muxed fragments concatenated into a local file, with no speaker playback,
  capture devices or network access. In `run.6y4yfq69`, E-AC-3 completed with
  1,295,840 decoded samples, first PTS 0, end PTS 26.9966667: 160 samples fewer
  than the reference. This is not an accepted repair or evidence of tvOS output.
  The exact origin of this native-reader discrepancy remains unresolved.

The strict FFmpeg comparison is retained, not relaxed. Native reader counts are
reported separately and cannot manufacture a pass. Four edit-list helper tests
cover versions 0/1, unchanged media/video bytes, repeat application, unsupported
edits/timescales and malformed boxes; the five existing helper tests also pass.
No Aether rebuild was needed for this metadata-only follow-up. Installed app,
production engines, credentials and Apple TV remain untouched; storage cleanup
retained reports and removed generated media.

Next investigation is confined to E-AC-3's native presentation boundaries: inspect
per-buffer timing/trim attachments and codec delay. An offset needs evidence.
Do not replace the missing samples with silence, re-encode, or move the whole track.

## Investigation of the 160-sample native discrepancy

The native reader now records compressed and decoded buffer boundaries, trim
attachments and decoded-byte hashes. Non-finite timestamps are recorded as null;
an initial diagnostic serialization failure (`run.n8kt2izj`) is retained.
`run.pmoj7phx` and `run.7q9cnjft` localized the source's final E-AC-3 packet:
its Matroska duration is 29 ms, with 128 samples of explicit discard padding,
although the compressed block decodes to 1,536 samples (32 ms). The prototype's
fragment used 1,392 ticks for that last sample duration. Native compressed output
also showed a 256-sample start trim and a shortened last block interval.

An opt-in `AIRCILLER_TAIL_DURATION_PROBE=1` corrects only the last explicit audio
`trun` duration from 1,392 to 1,536, using the decoded final source frame count
plus its explicit discard padding. It leaves packet bytes, fragment start times,
video and the exact presentation edit unchanged. This fixes the block-duration
metadata but **does not fix the native sample discrepancy** (`run.a7b5hdid`).
The compressed timeline grows by 144 ticks; decoded output remains 1,295,840.
Therefore the duration error alone is not the demonstrated cause of the 160.

A separate, non-fragmented MP4 reference is stream-copied directly from the same
source, then receives the same exact edit. In `run.oefhpgb1` and final
`run._5pmbtl6`, Apple decodes reference and candidate to exactly the same byte
hash (`b043959f5da19f774f9b52797754372484d7f2cca10c90adf067214b6102e955`),
sample count and presentation end. A separate AudioConverter prime-info query
returns zero leading/trailing frames; it does not explain the internal
AVAssetReader behavior. The reference itself fails exact PCM equality with the
Matroska source under FFmpeg (`referencePCMMatchesSource: false`). Thus native
reference equality is useful localization, **not an independent fidelity pass**.

The remaining 160 samples cannot currently be attributed solely to Aether: the
same result occurs without its packager. The precise shared MP4/native trimming
mechanism is still unresolved. No compensating shift, padding or re-encoding was
introduced. The acceptance gate remains failed and Apple TV was not used. AAC's
unchanged prior pass was reused; no general playback suite or production build
was repeated. The native helper compiles with strict Swift 6 and warnings-as-errors;
ten helper tests pass. The installed app is unchanged.

The next useful isolation is a standalone E-AC-3 decoder/input-boundary comparison
that separates intrinsic decoder output from MP4 edits. Another end-to-end movie
or receiver run would leave that distinction unresolved. Do not treat the byte-identical native reference
as authorization to waive the still-failing source-fidelity check.

## Initial timing observations (historical)

Aether returned from load in 0.144 seconds. Its published duration was still zero
at that point: session creation is not player readiness or first picture.
Snapshot completion took 3.577 seconds from launching the host, including process
startup, native setup and HTTP resource fetching (23,212,209 bytes).
AirCiller's probe and local HLS preparation took 0.103 seconds with an empty cache.
These are different boundaries and one sample. They do not demonstrate either
engine being faster at Play-to-picture. No such speedup is claimed.

## Validation and failures

The upstream release CLI built successfully with upstream warnings. Both the
new host and the baseline compiled with Swift 6 strict concurrency and
warnings-as-errors. Four snapshot tests cover local-only origin, complete VOD,
relative subtitle resources, cross-origin rejection and resource bounds.

The first attempt (`run.zgak0qag`) read the engine's asynchronously published
`currentAVPlayerItem` immediately after load and found no asset. The host now
reads `currentAVPlayer.currentItem`, the actual current item. This correction
made the local native URL available; the failed attempt is retained. It is not
an AirPlay rejection or engine codec failure.

After the comparison, the snapshot downloader was hardened to refuse redirects
before following them, and packet counts were added to future reports. Those
changes do not alter the retained media-parity evidence. Snapshot tests pass.

The existing complete AirCiller local gate from the preparation review remains
applicable to its unchanged production inputs. This prototype does not enter
the app build or CI. Rebuilding the identical production app would not validate
the new standalone host; that host was compiled and exercised separately.

All prototype processes exited. Generated media was pruned by the existing
storage guard; reports remain. Observed test storage is 3.15 GiB including the
new upstream build tools. No camera, microphone, digital receiver capture,
pairing or receiver playback was started. The installed application was not
opened, replaced or modified.

## Historical proposed next steps (superseded by closure above)

1. Trace the source and output timestamps and decoded initial AAC samples to
   classify the missing packet. Check a bounded E-AC-3 fixture as a distinct
   original-audio case, without hiding the AAC failure.
2. If original-content handling is accepted, attach an isolated transport host
   using AirCiller's unchanged AirPlay 2 controller. Compare the same finalized
   output on the receiver with the exact approved digital capture source.
3. Check HDR/DV plus selectable text/bitmap subtitles, seek, pause and control
   continuity before proposing migration. The first SDR sample proves none of
   these receiver outcomes.
4. Progressive output would require a separately approved exception to the
   complete-VOD invariant. This prototype deliberately snapshots final VOD and
   does not use the experiment to change that production rule.

The whole-engine prototype supersedes the earlier component-only deferral as an
authorized investigation, not as a shipping decision. Existing spatial-audio
observations in [the component review](AETHER_COMPONENT_REVIEW.md) remain scoped
to their original experiment and are not evidence for this new candidate.

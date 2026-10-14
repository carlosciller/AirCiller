# Audio expansion investigation

Implementation/preparation delivery, 14 October 2026. The 0.16.0 candidate
adds explicit PCM-to-FLAC preparation on HLS, validated locally and in the
bounded digital-output cases recorded below. SDR uses separate renditions with
the source's relative clock preserved; HDR without subtitles stays multiplexed.
The maintainer prohibited receiver tests during local preparation, then authorized
the exact Apple TV digital screen/audio source on 14 October 2026. Cameras and
microphones remain forbidden.
The installed application and engines are unchanged.

## Evidence boundaries

| Family | Included decoder | Current original-output policy | Next investigation | New receiver evidence |
| --- | --- | --- | --- | --- |
| PCM/LPCM | Integer PCM and `pcm_bluray` decoded in fixtures | Not accepted | Explicit PCM-to-FLAC implemented; original PCM requires receiver proof | Stereo, 7.1/WebVTT, Blu-ray 5.1(side), HDR mono |
| DTS / DTS-HD | `dca` present | Not accepted | Representative extension-bearing samples; a decoder listing does not prove Master Audio extension decoding | None |
| TrueHD | Present | Not accepted | Channel-based lossless output; do not promise Atmos objects | None |
| MP3 | Present | Not accepted | Packet-copy packaging and manifest signaling | None |
| AAC | Present | Generic `aac` accepted | Separate LC, HE v1/v2 and xHE profiles, signaling and sample requirements | None |
| FLAC | Present | Native, known layouts only | Retain channel-mask overrides before widening eligibility | Original 7.1 with/without WebVTT used as a diagnostic |
| ALAC | Present | Accepted | Explicit multichannel preservation checks | None for this investigation |
| Opus, Vorbis, MP2, WMA | Decoders present | Not accepted | Later candidates, without assumed original AirPlay support | None |

### The six validation layers

| Input | Actual reading/decoding | Copy-only packaging | Apple documentation | AirPlay session | Sampled output | Conservation |
| --- | --- | --- | --- | --- | --- | --- |
| Integer PCM/LPCM | 16/24-bit synthetic MOV and LPCM-framed M2TS | PCM copy investigated; not enabled | FLAC/fMP4 named by HLS authoring; original PCM session unresolved | Explicit conversion passed selected 48 kHz cases | Picture/audio/cues plus track changes observed | Complete normalized PCM, layouts, rate and packet timing verified at 48/96 kHz |
| DTS / DTS-HD HR / MA | Decoder/XLL parser inspected; representative decode not accepted | Not enabled | No application-specific acceptance established | Untested | Unobserved | Lossless-extension reference required; no DTS:X promise |
| TrueHD | Included decoder inspected; delivery not implemented | Not enabled | No application-specific acceptance established | Untested | Unobserved | Atmos objects not preserved by an assumed channel conversion |
| MP3 | Decoder present; sample delivery pending | Not enabled | Device format listing alone is insufficient | Untested | Unobserved | Packet/signaling checks pending |
| AAC-LC / HE v1/v2 / xHE | Native decoder handling inspected; profile fixtures pending | Existing generic AAC policy retained | Profile-specific authoring/signaling must be checked | No new profile acceptance claimed | No new profile observation | Existing manifest's generic LC signaling is a limit |
| FLAC | Actual decoded samples in local and receiver fixtures | Existing native layouts; rear-mask overrides rejected | FLAC/fMP4 stereo and multichannel documented | Original 7.1 diagnostic passed | Picture/audio and cues observed | Encoded frames, PCM/layout/timing checks kept separate |
| ALAC | Encoding/decoding experiment completed | No wider policy introduced | ALAC/fMP4 documented; layout acceptance separate | No new acceptance | Unobserved here | Encoder experiment relabeled side 5.1 and failed 7.1 samples; no universal fallback |
| Opus / Vorbis / MP2 / WMA | Included decoder listings inspected | Not enabled | Delivery investigation pending | Untested | Unobserved | No preservation claim |

The included engine is FFmpeg 9.0.1. Its native FLAC and ALAC encoders are
available. Its released build does not include the lavfi input. An initial
synthetic-source attempt failed for that reason; no host-engine substitution was
used. The research tool now generates integer PCM fixtures with the Python
standard library and sends them to the pinned engine.

## First local matrix

`Scripts/research_audio_formats.py` requires explicit FFmpeg/ffprobe paths and a
fresh output directory. It generates distinct tones for each channel, then tests
fragmented MP4 copy, FLAC and ALAC. Cases cover little/big-endian integer 16/24-bit
PCM, 48 kHz, mono, stereo, rear `5.1`, `5.1(side)` and `7.1`.

The first completed matrix contains 60 cases. Copy passed exact decoded sample,
layout and sample-rate comparisons in 16/20; FLAC in 16/20; ALAC in 12/20.
These counts are local container results, not supported-format declarations.

- Original PCM copy preserved samples in all cases, but the probe lost the mono
  layout label in four cases. This still fails the current strict layout gate.
- FLAC preserved decoded samples, but relabeled rear `5.1` as `5.1(side)` in four
  cases. Do not enable those cases or silently relabel their speakers.
- ALAC relabeled `5.1(side)` as rear `5.1` in four cases. It also failed the
  sample comparison for all four `7.1` cases, with output probed as `6.1(back)`.
  Investigate this separately; ALAC is not a universal safe fallback.

The source tones contain independently identifiable channel content. Comparison
decodes source and prepared output into interleaved signed 32-bit little-endian
PCM, without requesting a new rate, layout or channel count. It compares complete
byte length and SHA-256. Sixteen-bit sources intentionally originate from a
24-bit fixture; comparison uses the actual encoded source, not the pre-encoding
waveform. This experiment does not yet prove video identity, packet timing,
Blu-ray PCM framing, HLS manifest correctness, subtitle behavior or tvOS output.

Private synthetic files and detailed results remain in the ignored directory
`.build/audio-research-20261013-2/`; the failed first attempt remains separate.
No credentials, receivers, cameras or microphones were accessed.

## Chronological implementation record

This record retains failed and superseded configurations. The final separate-SDR
configuration and its acceptance are summarized under Final validation and follow-up.

### Production-service media comparisons

The first movie matrix remuxed the synthetic PCM into Matroska. The container
did not retain the channel-layout labels; the candidate rejected all twenty
inputs. Those results remain in `.build/pcm-hls-validation-20261013-1/`.
This is a real eligibility boundary, not evidence that PCM samples were corrupt.

A second matrix used MOV, preserving the source layout. All sixteen eligible
conversions retained exact decoded PCM, rate and layout and copied all video
packets in order. However, separate audio/video output changed relative timing
by 83 ms. The run failed and is retained in
`.build/pcm-hls-validation-20261013-2/`. No tolerance was relaxed.

The candidate now uses a multiplexed HLS rendition only for the new PCM mode.
Its SDR master declares the embedded audio without a separate audio URI and
retains selectable WebVTT. Existing modes keep their previous packaging choices.
The following 48 kHz and 96 kHz movie matrices each passed sixteen positive
cases and four specific rear-5.1 rejections. Positive cases retained all decoded
sample bytes, channel layout, sample rate and ordered video packet hashes;
relative first and final audiovisual timestamps matched exactly. Each source
has eight seconds of audio, multiple HLS fragments and selectable text cues.
No receiver was contacted.

The 96 kHz negative tests require the precise eligibility error, normal exit
code 2 and no prepared fragments. This strengthens the initial 48 kHz rejection
check, which accepted any nonzero exit. The earlier report remains unchanged.
Reports are `.build/pcm-hls-validation-20261013-3/` and
`.build/pcm-hls-validation-20261013-96k/`.

Manual audio adjustment is excluded from the new mode while the separate timing
repair remains unresolved. Representative disc-derived media and receiver
acceptance remain pending. The 48 kHz run measured a median 0.054 seconds wall time and 0.054
seconds child-process CPU for these short preparations, and 3.02 to 6.44 MB of
prepared files. These are local fixture measurements, not startup forecasts for
movies or an improvement over a matched baseline. A local candidate build
measured 155,993,955 logical bytes before the shared-clock change; final size and
a matched-signing baseline remain to be measured.

### HDR timeline verification

The initial HDR matrix was rejected by the helper's container-duration assertion:
its source MOV has a 167 ms video presentation offset, so container duration is
not the HLS decode interval. Inspection showed all 192 video packets retained,
with identical presentation/decode timestamps and the complete eight-second
audio waveform. The failed report remains in
`.build/pcm-hls-validation-20261013-hdr-final/`.

The verifier now independently checks every video PTS/DTS against the source
allowing only a shared constant origin, checks playlist duration against the
output packet decode interval, and checks the service's duration against the
playlist. The existing 2 ms synchronization bound was not increased. With this
stronger timeline check, sixteen eligible HDR PCM cases and four rear-5.1
rejections passed in `.build/pcm-hls-validation-20261013-hdr-timeline/`.
This is HEVC/PQ HLS without subtitles, not direct MP4, Dolby Vision metadata
acceptance, or receiver/HDR-display verification.

The same verifier also passed sixteen SDR cases with selectable subtitles and
four specific rear-5.1 rejections in
`.build/pcm-hls-validation-20261013-sdr-timeline/`. Neither run contacted a device.

### Blu-ray framing

The included `pcm_bluray` encoder generates actual LPCM-framed M2TS synthetic
inputs from the known waveform. Its decoder's pinned 9.0.1 source accepts
16/24-bit headers and explicitly rejects 20-bit headers, despite the decoder's
descriptive name mentioning 20 bits. Twenty-bit Blu-ray PCM is now ineligible.

The first Blu-ray batch exposed an omitted probe field: 16-bit LPCM reports
`sample_fmt=s16`, with `bits_per_sample=0` and no raw precision. The candidate
uses this decoder-specific signed16 result to establish precision. It never
infers 24 bits from an `s32` sample buffer; explicit raw precision is required.

The initial packet-hash check also rejected TS-to-MP4 video framing changes,
even when picture content was identical. The corrected check reuses the existing
Annex-B coded-picture verifier, retains packet-count checks and keeps the audio,
layout and timestamp checks. It does not compare decoded video alone or relax
the synchronization tolerance. The original failed batch is retained in
`.build/pcm-hls-validation-20261013-bluray48/`.

Eight repeated 48 kHz cases passed for 16/24-bit LPCM, mono, stereo, side 5.1
and 7.1. Exact decoded audio, coded video, packet count, channel labels and
relative start/final timestamps were preserved. The M2TS clock begins above
zero. The report is `.build/pcm-hls-validation-20261013-bluray48-2/`.
These fixtures exercise real Blu-ray framing, not disc navigation or encryption.
The subsequent 96 kHz batch below exercises the strict decoder-error policy.

The final strict-error Blu-ray batch at 96 kHz passed the same eight cases with
`-xerror` and decoder error detection enabled. Its report is
`.build/pcm-hls-validation-20261013-bluray96-final/`. Unsupported 20-bit headers
and a precision-header corruption halfway through a valid LPCM track were then
rejected. The first failed during eligibility; the second reached decoding and
stopped with a specific decoder error. Neither produced a master playlist and
the source was unchanged. `.build/pcm-corruption-20261013-1/` retains both cases.

The strengthened negative runner requires the expected eligibility exit/error
for 20-bit headers and the decoder-specific failure for midstream corruption.
An unrelated rejection cannot pass these cases. It also cuts a synthetic PCM MOV halfway
through its container and requires a probe rejection before any output directory
exists. All three cases passed in `.build/pcm-corruption-20261013-final/`, with
both source hashes unchanged. This does not claim that every truncated transport
stream is detectable: a shortened but structurally valid TS can describe a shorter
movie without declaring the missing tail.

### Cache and comparative resource checks

The real service retained a PCM-to-FLAC base, reused its media byte-for-byte on
the next session and did not reuse it for E-AC-3. New-mode keys include precision
and sample rate. Existing modes keep their prior keys.

Three preparations per mode used one eight-second, 24-bit/48 kHz 7.1 MOV with
the same engine and subtitles. Median wall/child CPU times were 0.061/0.078
seconds for the existing E-AC-3 choice and 0.070/0.085 seconds for lossless FLAC.
Prepared files measured 3,517,901 and 6,435,467 bytes respectively. E-AC-3 reduces
this input to 5.1 and adds loss; it is not an equivalent-quality reference.
The cached FLAC replay measured 0.025 seconds wall and 0.024 seconds child CPU.
The operating-system cache was not reset. These short-process measurements do
not predict full-movie preparation, AirPlay connection or first television output.
The report is `.build/pcm-preparation-metrics-20261013-1/`.

A fresh ad hoc build of the unchanged HEAD source reproduced the published
0.15.0 logical size, 155,889,320 bytes. A matched ad hoc audio candidate measured
155,935,330 bytes, an increase of 46,010 bytes before the final sidebar adjustment.
The final matched ad hoc candidate including that adjustment measures 155,913,192
bytes: 23,872 bytes above the baseline (0.0153%). This is a local candidate,
not a published release bundle. The test icon and credential helper
must not be counted as audio-engine growth. No engine or dependency changed.

### Native interface review

An offline UI candidate opened a synthetic 7.1 MOV without starting playback.
Original was selected initially; choosing FLAC displayed the codec-change and
zero-audio-adjustment explanation. Cancel preserved Original. Explicit Apply
changed the visible audio plan without preparing media or contacting a receiver.

Changing the draft audio offset to +0.05 seconds then exposed a UI defect: Apply
remained enabled although the playback/service guards would reject the choice.
The candidate now disables Apply for an invalid output and explains recovery.
It also avoids duplicating the conversion explanation when audio options are
expanded. Focused draft-policy regressions passed; the corrected native interaction
remains pending. A fresh launch of the rebuilt candidate confirmed the complete
Audio and Subtitles inspector visible even without a selected movie. Its toolbar
button hid and restored the inspector, with the action label changing accordingly.
Applying a draft no longer dismisses the inspector; this final interaction still
needs native readback with a selected movie.
The rebuilt candidate subsequently opened and analyzed that same synthetic MOV
with the complete inspector still visible and Original selected. Further control
interaction could not be verified: coordinate actions reported
`noWindowsAvailable`, while the accessibility snapshot remained available and
keyboard actions did not change it. This is an automation observation gap, not
evidence that Apply or the audio selector worked or failed in the running app.
The next fresh launch resolved that interaction gap. Selecting FLAC and applying
it left the inspector visible, changed the movie's audio plan and disabled Apply
with no remaining edits. Increasing audio timing to +0.05 seconds kept Apply
disabled and displayed the recovery warning. Opening another synthetic PCM MOV
discarded the unapplied timing draft, selected Original and left the refreshed
inspector visible. No playback was requested. After closing the candidate, only
the two owned synthetic queue/recent entries were removed; the previous arrays
matched their saved baseline before restoration.
The test app was closed and only its synthetic queue/recent entry was removed,
after verifying all prior entries still matched the saved test-domain baseline.
The daily app and preferences were not modified.

### Other families

The pinned DTS decoder exposes `core_only=false` and contains the XLL extension
parser. It also has XLL error-concealment/recovery paths; these facts do not prove
that a particular DTS-HD MA sample retained its lossless extension. No DTS family
has been newly enabled. Representative DTS-HD MA/HR samples and decoded reference
comparisons are required for a later phase. Encoding channel audio into FLAC
cannot establish retained DTS:X objects or reconstruct a lossy core's missing data.

TrueHD decoding is present, but no TrueHD-to-FLAC delivery or Atmos-object
preservation has been accepted. The current AAC decoder contains USAC and HE
handling, while the original manifest builder still declares AAC-LC generically.
HE v1/v2 and xHE require profile-specific signaling tests before broader claims.
MP3, Opus, Vorbis, MP2 and WMA remain research candidates, not new input promises.
The Apple HLS specification's named codecs establish specification support, not
acceptance in this application's AirPlay session.

Lossless conversion now requests strict decoder errors and stops on an FFmpeg
error. Corrupt-input and cache checks are recorded above; final native draft
interaction and receiver acceptance remain separate checks.

Source: the included source archive's `libavcodec/pcm-bluray.c` and
`pcm-blurayenc.c`, matching [FFmpeg 9.0.1](https://github.com/FFmpeg/FFmpeg/tree/n9.0.1/libavcodec).

The candidate probes sample rate and effective precision, retaining raw precision
when declared. A separate output choice requests FLAC encoding without a rate,
channel-count or filter override. Original remains the default. Eligibility
requires integer PCM 16/24-bit or Blu-ray PCM 16/24-bit, positive sample rate,
and a known mono, stereo, `5.1(side)` or `7.1` layout matching channel count.
Unknown or contradictory properties are rejected. Blu-ray framing still needs
representative media validation; eligibility alone is not acceptance evidence.

The tracks picker disables this choice on the direct HDR/subtitle route. The
coordinator independently rejects a stale or invalid choice before authorization
and preparation. The HLS service also rejects invalid tracks before processes
or cache lookup. Direct MP4 has no new encoder path; all existing modes retain
their prior commands. Original PCM is still not declared supported.

Focused eligibility and command regressions cover missing precision/rate/layout,
rear-versus-side 5.1, inconsistent channel count, float PCM, unsupported codecs,
direct-route exclusion and absence of resampling/downmix/video encoding options.
The new wording is present in English and Spanish. The strict application gate
passed after the sidebar and draft-policy corrections. The final repeated gate
also passed its code tests; a public-prose failure was corrected and that gate
resumed at publication checks, followed by the strict build and bundle checks,
ending in `AirCiller local checks: OK`. The failed output was retained. No device
was opened by these simulated tests or capture-tool compilation.

## Receiver checks, 14 October 2026

The rebuilt candidate first passed the three original-audio regression cases:
direct HDR with subtitles, SDR HLS with subtitles and SDR HLS without subtitles.
Receiver controls and sampled motion/audio/cue checks passed separately in
`.build/playback-checks/capture-run-k5newkbl/`. All owned processes ended.

The check plan now accepts explicit `audioOutput: losslessFLAC` only for HLS
control cases. It does not widen original eligibility or automatically approve
other conversions. Capture configuration requires a matching explicit PCM case
and local fixture override. The Swift model and capture safety tests passed,
followed by the complete strict gate after correcting retained formatting errors.

The first PCM trial, 24-bit/48 kHz 7.1 with WebVTT, failed immediately after a
receiver playing notification: a terminal stopped event arrived before the stable
output window. The saved digital frame showed the generated picture with a loading
indicator, not sustained playback. Cleanup passed. This remains an unsuccessful
case in `.build/playback-checks/capture-run-07mvjov3/`.

The isolated 16-bit/48 kHz stereo PCM case without subtitles passed explicit FLAC
selection, startup/media requests, receiver progress, pause/resume, acknowledged
seeks, the receiver's destination and cleanup. Captured picture moved, digital
audio was non-silent and no subtitle cue was observed. The report is
`.build/playback-checks/capture-run-eo59z8od/`. This is not a pass for 7.1 or
subtitles. Physical speaker layout and
losslessness after receiver processing remain unverified.

The crossed batch passed stereo PCM-to-FLAC with WebVTT, but 7.1 without
subtitles stopped immediately after its initial playing notification too.
Both cleanup checks passed; `.build/playback-checks/capture-run-k62gvzm8/` retains
the two outcomes separately. This rules out subtitle presence as the necessary
trigger in these fixtures. It does not establish whether 7.1 FLAC itself or the
new multiplexed rendition is responsible.

An independent diagnostic converts only the synthetic 7.1 fixture into a FLAC
source and uses the existing Original output route. Its full decoded signed32
PCM bytes match the PCM source; metadata retains 24 bits, 48 kHz and 7.1. This
comparison passed receiver controls and sampled motion/audio without subtitles,
with cleanup confirmed, in `.build/playback-checks/capture-run-hlfb1woi/`.
It is not application fallback or a change to original-output policy. The same
7.1 sample content is accepted by the existing separate-audio HLS path but stops
in the new multiplexed path. This localizes investigation to packaging/rendition
differences; it does not yet identify a specific invalid field or justify reducing
channels, discarding the failed case, or declaring the PCM expansion complete.

Local inspection of fresh service outputs found 2,813 encoded FLAC packets with
identical ordered sizes and SHA-256 hashes in multiplexed and separate packaging.
Their presentation origins differ by 83 ms. STREAMINFO also differs: the newly
encoded fragmented output has unset totals/MD5, while the completed source has
those values. Neither difference has yet been proven to cause the receiver stop.

A bounded candidate experiment removes the alternative-audio group from the
single embedded-audio variant, while retaining FLAC in CODECS and selectable
WebVTT. Original separate-audio manifests are unchanged. The
[HLS specification](https://www.rfc-editor.org/rfc/rfc8216.html#section-4.3.4.2)
defines AUDIO as an optional variant attribute. This is a receiver-comparison
hypothesis, not an accepted repair. No sample, channel or packaging clock changes
are included; its fresh check build and strict gate passed.

The ungrouped candidate passed 7.1 PCM-to-FLAC without subtitles in
`.build/playback-checks/capture-run-zmq92o0_/`: receiver controls, sampled motion
and digital audio, with completed cleanup. The full strict gate passed too.
The subsequent 7.1 WebVTT case still stopped after its initial playing event,
recorded separately in `.build/playback-checks/capture-run-yad6cgo4/`. The two
remaining fixtures were not run because the supervisor stops on an unsuccessful
case. This is a partial compatibility result, not complete acceptance of the
manifest change or the expansion. Separate original-FLAC-with-WebVTT and remaining
PCM cases are being evaluated without changing channels or source media.

The original separate-audio 7.1 FLAC case with WebVTT then passed in the first
case of `.build/playback-checks/capture-run-3rmtjn0i/`. This further confines the failure
to the new multiplexed combination, not general 7.1 plus WebVTT acceptance.

The fresh production-service SDR matrix with the ungrouped master passed sixteen
eligible cases and four specific rear-5.1 rejections in
`.build/pcm-hls-validation-20261014-master/`. The complete sample, layout, coded
video and packet-timeline comparisons remained unchanged.

The completed `.build/playback-checks/capture-run-3rmtjn0i/` batch also passed
24-bit/48 kHz Blu-ray-framed LPCM 5.1(side) converted explicitly to FLAC without
subtitles. The mono 16-bit HDR case passed all receiver controls and cleanup,
with 65 non-silent digital measurements and 25 changing central frames, but its
overall output verdict remains inconclusive (`expectedPictureNotObserved`).
That HDR video came from an existing private movie sample; the evaluator expected
the generated color pattern used by the HDR-HLS scenario. The extracted input
frame shows a film logo, not that pattern. A valid pattern fixture or an independently
validated source-identity evaluator is required before audiovisual acceptance.
The saved failure has not been reassessed as passing.

The first replacement synthetic HDR pattern omitted static HDR10 mastering-display
and content-light messages. The production metadata injector rejected its local
preparation with `unsupportedConfiguration`; the corresponding receiver attempt
is retained in `.build/playback-checks/capture-run-gmemr682/`. It reached no stable
playback window. A second new fixture includes these messages and passed local
preparation. Its generated HEVC/PQ video is QA-only; the explicit development
encoder is not bundled or used to encode movies in AirCiller.

PCM preparation now has a distinct `hls-pcm-source-clock-v2` cache signature.
Unreleased packages prepared with the previous clock cannot be reused. Existing
output modes retain `hls-base-v1`. The check runner also supports explicitly
selected FLAC for bounded HLS track-change/cancellation scenarios, with the same
exact-source capture rules and no automatic conversion approval. New model and
configuration regressions and the full strict gate passed.

The corrected HDR pattern passed receiver controls and sampled picture/audio in
the first case of `.build/playback-checks/capture-run-7m3mazc9/`: 27 changing
frames, 20 matching pattern frames and 61 non-silent digital measurements. The
FLAC track-change case passed all four receiver phases and cleanup. Three phases
also passed their independent picture/cue/tone checks; the audio-change phase
lacked enough captured frames in its five-second window. The overall verdict
remains inconclusive. Explicit FLAC track-change windows now retain eight seconds;
frame counts, cue identity, tone requirements and receiver checks remain unchanged.
Original-mode windows retain their previous duration. This adds observation time
and does not change the application or rewrite the failed report.

## Final validation and follow-up

### Separate SDR clock repair candidate

`Scripts/research_pcm_clock.py` invokes the production command builder with
receiver-free diagnostic options. Three short synthetic sources (24-bit 7.1 MOV,
16-bit stereo MOV and 96 kHz Blu-ray LPCM 5.1(side)) reproduced the 83 ms error
under per-output `avoid_negative_ts=make_zero`. Disabling that shift preserved
complete PCM bytes, coded video and relative first/final timestamps exactly in
all three. Negative-CTS-offset variants failed the same preservation contract;
their results remain in `.build/pcm-separate-clock-20261014-1/`.

The candidate now uses separate SDR renditions for explicit PCM-to-FLAC, with
per-output negative-timestamp shifting disabled only in that mode. HDR without
subtitles remains multiplexed. Original, E-AC-3 and stereo-AAC arguments retain
their existing timestamp flags. The abandoned embedded-audio master experiment
has been removed from the writer; separate audio retains its URI and channel
declaration. The legacy manual-audio-adjustment defect is untouched.

Fresh production-service matrices passed sixteen PCM positives/four specific
rejections and eight Blu-ray LPCM cases. Full decoded samples, speaker labels,
coded video and packet-based timing passed in
`.build/pcm-hls-validation-20261014-separate/` and
`.build/pcm-hls-validation-20261014-separate-bluray/`.
The corrected candidate passed 24-bit 7.1 PCM-to-FLAC with WebVTT and 16-bit
stereo without subtitles in `.build/playback-checks/capture-run-b9t2qk19/`.
Both cases passed explicit conversion selection, receiver progress, pause/resume,
seek acknowledgements/destination, sampled moving picture/non-silent digital
audio and their expected cue presence/absence. Cleanup passed for both. This
resolves the reproduced 7.1-with-subtitles failure in the tested short fixture;
it does not establish physical speaker routing or whole-movie reliability.

The final scenario batch, `.build/playback-checks/capture-run-4dibypx7/`, passed
all four independent FLAC track-change windows: original cue/880 Hz, replacement
cue/880 Hz, alternate audio/440 Hz, and subtitles off/440 Hz. It also observed
the real preparation process, cancelled it through Stop, confirmed cleanup and
observed no late playback. The final Blu-ray LPCM 5.1(side) case passed moving
picture, digital sound, receiver controls and cleanup through the corrected SDR
path. All test processes ended. The installed app was not replaced.

Final strict checks passed. The final corrupt-input rerun rejected 20-bit headers,
midstream LPCM corruption and a truncated MOV in
`.build/pcm-corruption-20261014-source-clock/`, without modifying source hashes.
The prepared-media cache cold/warm round trip retained identical base bytes and
did not cross output modes under the new cache signature.

A final copy-only check of the separate Original 7.1 FLAC diagnostic verified
1,440 coded video units and identical encoded audio using
`Scripts/verify_stream_copy.py`. It retains the existing Original route's 83 ms
start offset. The new PCM conversion's exact clock checks are separate; this
delivery does not repair or relabel that legacy Original timing behavior.

The final code review removed an unused packager parameter left by the rejected
multiplexed experiment. The last strict suite completed with
`AirCiller local checks: OK`; a subsequent help invocation returned usage status
1 in the enclosing command. That help status is unrelated to the completed suite.
No playback behavior changed in this cleanup: the validation predicate and
package/clock commands are identical to the accepted receiver candidate.

The final matched ad hoc bundle is 155,913,144 logical bytes, 23,824 bytes above
the unchanged 0.15.0 baseline. Engines/dependencies are unchanged. On the same
eight-second 24-bit/48 kHz 7.1 fixture, three cold preparations per mode measured
these medians:

| Output | Wall seconds | Child CPU seconds | Prepared temporary bytes |
| --- | ---: | ---: | ---: |
| E-AC-3, reduced to 5.1 with loss | 0.059 | 0.072 | 3,517,901 |
| FLAC, original samples and 7.1 | 0.068 | 0.084 | 6,436,040 |

Warm FLAC cache reuse measured 0.027 seconds wall and 0.028 seconds child CPU.
These are short local measurements, with no OS-cache reset or television-startup
forecast. The report is `.build/pcm-preparation-metrics-20261014-final/`.

Follow-up cases: representative legal disc-derived LPCM beyond generated framing,
sample rates and device/speaker setups outside the recorded matrix, and PCM
conversion on direct HDR MP4 with subtitles. Wider AAC profile-aware signaling
and reference-backed DTS/TrueHD lossless decoding are separate deliveries. The
current phase adds one bounded audio expansion; it does not enable all families.

## Delivery audit

| Requirement | Current evidence and boundary |
| --- | --- |
| State, pinned engines and routes | Source/diff review; strict dependency-lock/bundle checks; engines unchanged |
| Ordered family research | Six-layer matrix, included decoder/source inspection, PCM/FLAC/ALAC experiments; unimplemented families remain explicit |
| Original preferred, no hidden loss | Existing-mode commands retained; explicit PCM eligibility, output selection, route/timing guards and negative tests |
| Native experience and bounded implementation | Inspector native readback, bilingual strings, stale/invalid draft guards; only HLS gains conversion |
| Preservation and behavior | Real service PCM/layout/video/timing matrices, corrupt-input tests, immutable cache round trip, original packet-copy verification, receiver and digital-output reports |
| Documentation and measured impact | Compatibility/roadmap/unreleased notes, exact matched bundle bytes and repeated local resource measurements; no publication or installed-app replacement |

The accepted receiver candidate and final cleanup have identical packaging commands
and validation predicates. Cleanup only removed an unused private argument and
equivalent conditional spelling. The completed strict suite validates the final
source; earlier failed runs remain separate. Physical speaker/Atmos routing,
physical HDR fidelity and full-movie reliability are unverified, as required by
the digital-capture evidence boundary.

Rear `5.1`, unknown layouts, 20-bit LPCM and direct HDR MP4 with subtitles remain
outside this expansion. Original stays preferred. No DTS/TrueHD object-based
metadata preservation is claimed. Publication and installation are a separate
phase; this candidate is not a released compatibility promise.

## 0.16.0 publication preparation

The release candidate is version 0.16.0, build 64. The complete strict local
suite passed again after the release metadata and long-pause fixture support
were added. The public ad hoc bundle measures 155,913,144 logical bytes, within
the unchanged 165,000,000-byte budget. Distribution audit confirms a structurally
valid signature and bundled runtimes; Developer ID, Hardened Runtime,
notarization and Gatekeeper acceptance remain absent under the current public
signing policy.

Compared with the accepted receiver candidate, production playback sources and
pinned dependencies are unchanged. Only version metadata and test-only support
for an explicit PCM long-pause fixture were added. Existing receiver-control,
HTTP serving, power assertions, bridge commands, natural-end/Playlist handling
and remote-command implementation remain unchanged from the released baseline.
Earlier physical remote and natural-end evidence is retained for those unchanged
boundaries; new digital checks do not certify physical remote interactions.

Two fresh PCM/WebVTT long-pause runs retained the same session for six minutes,
resumed at second 15 without reload, and confirmed stop/cleanup. The first,
`capture-run-fwsnfe4n`, used the multitone 7.1 fixture against a scenario expecting
880 Hz. Its tone verdict is inconclusive, not a playback failure or a pass.
The corrected run, `capture-run-qtist906`, used the dual-track stereo fixture.
Its resumed window observed eight frames, visible cues, motion and twenty
matching 880 Hz audio measurements. The initial five-second capture window had
insufficient frames, so the whole raw report remains inconclusive.

Initial-output evidence is carried from `capture-run-4dibypx7`: twelve frames,
visible cues and thirty-two matching 880 Hz measurements on the identical source
SHA-256 `a73d39ed10a9125455fbca4f24eada3a68510f5698ec1ef01e8c0ca6d1d531d3`.
Production playback sources and pinned engines are unchanged between these runs;
release metadata and the test-only long-pause admission are the only differences.
Acceptance combines that established initial output with the new same-session
six-minute hold and fully observed resumed output. Neither inconclusive report
is relabeled as a complete batch pass. Physical remote and speaker limitations
remain as stated above.

The archive and signed feed verify with Sparkle's official tools. Applying the
63-to-64 delta to the downloaded public 0.15.0 reconstructs a strictly verified
0.16.0 bundle with identical file contents and symlinks (mtime differences only).
Exact-commit GitHub CI and an isolated updater check are separate release gates.
The daily-use installed app has not been replaced.

## Primary references

- [Apple HLS authoring specification](https://developer.apple.com/streaming/hls-authoring-specification-for-apple-devices.html): FLAC/ALAC in fMP4, stereo/multichannel requirements and AAC signaling.
- [Apple TV specifications](https://www.apple.com/apple-tv-4k/specs/): device-wide audio formats; not a guarantee of AirPlay acceptance.
- [FFmpeg codecs](https://ffmpeg.org/ffmpeg-codecs.html): consult alongside the actual included decoder/encoder listings.
- [Existing FLAC evidence](FLAC_AUDIO.md) and [deferred audio timing repair](HLS_AUDIO_TIMING.md).

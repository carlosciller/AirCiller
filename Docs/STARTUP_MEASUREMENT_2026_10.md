# Startup measurements, October 2026

Recorded on 19 October 2026 against checkout
`172bf019848cb24648429b6b41c5ba586733e8de`. Application sources, resources,
locked engines and build inputs match released 0.17.3. No playback implementation
was changed and no update was installed. The initial local campaign opened no
device; the subsequent live campaign below used only the approved digital Apple
TV screen/audio source after the maintainer confirmed it was free and awake.

## Status and next gate

**Local timings, five detailed HLS observations and a four-run capture comparison
are complete. Exact continuous
Play-to-output onset remains inconclusive because of capture audio gaps.**
The initial local campaign ran while the Apple TV was unavailable. After the
maintainer explicitly released it for measurement, a rebuilt isolated check app
ran two HLS observations: the original sampler and one instrumented diagnostic.
Both passed captured playback output; neither passed the stricter onset gate.
A separately authorized, single further observation measured AirPlay sub-stages
using a timing-only launcher. It also passed output, with inconclusive onset.
It was not a retry intended to produce a passing onset number.
A later, single successful HTTP-observer run added per-response chronology;
its earlier launch attempt stopped before playback, as recorded below.
A directed follow-up then separated header processing, file reads and body-send
processing in one further observation, without changing production playback.

Historical captured playback passed its output checks, but the paired startup
campaign in [the earlier record](STARTUP_OPTIMIZATION.md#phase-2-receiver-checks-12-september-2026)
had missing startup audio samples. All seven current captured onset reports were
inconclusive. The two capture-free observations intentionally provide no
audiovisual-onset evidence.
Those recordings cannot supply a valid current end-to-end baseline. Do not turn
receiver confirmation, an HTTP request or local preparation into first output.

## Method

An isolated optimized CLI linked the current production preparation sources and
the existing `HLSPreparationPerformanceBenchmark.swift`, using Swift 6 strict
concurrency and warnings-as-errors. A separate isolated entry point timed the
actual `MediaProbeService.probe` call. Both used the pinned bundled FFmpeg and
ffprobe. The benchmark touched neither daily preferences nor the daily cache.

Inputs were existing synthetic H.264/AAC fixtures with embedded text subtitles:

- Short: 13,865,608 bytes, 18.026167 seconds, with SRT and ASS.
- Large: 2,218,226,312 bytes, 2,883.308053 seconds, created historically by copying
  the short fixture repeatedly. This is not a representative feature-film encode.

Five probe calls were measured per input. Preparation used five repetitions per
short-input codec/mode and three per large-input mode with SRT: 39 samples total.
Mode order rotated. Warm app-cache fills, probing, fixture hashing and byte
comparisons were outside preparation timing. The operating-system file cache
was not purged; **empty app cache does not mean a cold disk**. These samples do
not establish a production tail percentile or external-drive performance.

All completed samples retained matching served-file inventories, duration and
source hashes across modes. File bytes and hashes were checked after timing.
Large generated packages were discarded only after verification, retaining the
reference package and all sample reports. Peak resource polling and filesystem
cache effects remain part of the experiment's limits.

An initial harness attempt incorrectly invoked the historical comparator, which
requires a frozen-baseline sample, on a current-only reference. It was rejected
and excluded. The completed campaign uses explicit current-to-current inventory,
duration, hash and byte comparisons; the historical comparator was not weakened.

## Fresh local results

Seconds, median. Individual large-input samples follow the table. Preparation ends at a
complete validated local VOD, before local AVPlayer and AirPlay startup.

| Input | Probe | Cache disabled | Empty app cache | Warm app cache |
| --- | ---: | ---: | ---: | ---: |
| Short, SRT | 0.01055 | 0.02814 | 0.03339 | 0.01562 |
| Short, ASS | Same input/probe | 0.02749 | 0.03294 | 0.01549 |
| Large, SRT | 0.01063 | 1.50631 | 1.86825 | 0.95734 |

The large-input observations were:

- Disabled: 1.829623, 1.506306, 1.469141 seconds.
- Empty: 2.215628, 1.868246, 1.861572 seconds.
- Warm: 0.941113, 0.957344, 0.969122 seconds.

For that input, warm reuse reduced median local preparation by 0.549 seconds
versus disabled caching and 0.911 seconds versus first admission. First admission
cost 0.362 seconds more than disabled caching. These are differences between
observed medians, not promised savings for movies or a measured end-to-end gain.

Large-input stage medians identify opportunities, not additive components:

- Packaging without cache: 1.318 seconds.
- Storing a newly prepared base: 0.358 seconds.
- Warm cache checkout: 0.728 seconds.
- Final validation: 0.077 to 0.102 seconds.

The subtitle span lasts 0.858 seconds on warm reuse, but it starts before parallel
extraction and ends after both branches join and subtitle playlists are finalized.
It includes waiting for the base/cache branch. It does **not** establish that
subtitle extraction itself costs 0.858 seconds. Do not sum overlapping spans.

## Fresh live measurements

The unchanged 0.17.3 playback implementation played the same synthetic 60-second
H.264/E-AC-3 clip with a fresh six-digit subtitle identifier. Each run used its
own empty HLS cache. Authorization and source readiness preceded Play; a
five-second capture preroll was outside the measurement. The starting point was
the check runner's explicit call to `coordinator.start(at: 0)`, after analysis.

All times below are seconds from that Play request, except the named stage
duration. They are two individual observations, not a median or tail estimate.

| Boundary | Original sampler | Instrumented sampler |
| --- | ---: | ---: |
| Local preparation/server/asset ready, before AirPlay call | 0.108 | 0.115 |
| AirPlay call duration, including waiting for receiver playback | 4.732 | 4.593 |
| Helper reports accepted command | 1.585 | 1.544 |
| Receiver reports playing | 4.813 | 4.692 |
| First identified tone sample | 5.155 | 5.080 |
| First identified moving picture with fresh subtitle | 5.308 | 5.156 |
| Audio signal confirmed by three consecutive samples | 5.565 | 5.493 |
| Picture confirmed by two consecutive samples | 5.841 | 5.679 |

The last four rows are **first positive captured samples and their confirmation**,
not certified first audible/visible onset. The unchanged strict evaluator rejects
both timing reports with `audioSamplingGapAtStartup`: the audio gaps were 1.249
and 1.194 seconds. Missing samples are not silence, so no complete end-to-end
latency, speedup, median or percentile is claimed. No physical speaker or panel
timing was measured. Playback output and timing validity are separate verdicts.

The diagnostic sampler added only PNG-write duration and source presentation
timestamps to the private sample records; source selection and capture/evaluator
criteria were unchanged. Maximum PNG handling during startup was 0.035 seconds.
The 1.194-second callback gap also had a 1.179-second gap in source audio
presentation timestamps. This does not support blaming that gap on a one-second
PNG write. It suggests a source/delivery discontinuity, without establishing its
root cause. An asynchronous capture rewrite was therefore not attempted.

The broad AirPlay span contains Python helper launch/imports, discovery,
authentication, session/queue setup and waiting for playback confirmation. It is
not a measurement of networking or pyatv overhead alone. Roughly 3.2 seconds
elapsed between accepted and playing. The trace's very short receiver-request
span is a check after AirPlay returns, not the actual first HTTP-arrival time.
These sub-boundaries need finer attribution before choosing an optimization.

Both runs confirmed Stop, runtime cleanup and deletion of their isolated caches.
No sampler, check app or analyzer process survived. The installed app executable
remained `c69732b5196a14936339b672b918ad85fe01feb7f0a7368a2f796fb6af11d824`.
No camera, microphone, pairing reset, permissions change or library update was used.

## Detailed AirPlay sub-stage observation

The maintainer requested the 4.6-second AirPlay span be attributed without
optimizing the engine. Existing controls retained accepted/playing events but
not the internal phase times; the bounded historical system-log query returned
no matching retained phase records. One additional HLS startup was therefore run.

A separate copy of the check app used a private observer launcher. It loaded
the byte-identical original helper and wrapped selected calls with monotonic
begin/end markers. Original arguments, return values, exceptions, protocol
parameters and call ordering were retained. Fixed stage names and elapsed times
were recorded, not arguments, payloads, credentials or device details. The
ordinary source tree, bundled engine, installed app and existing check app were
unchanged. The observer copy retained the existing local development signing
identity and passed strict nested signature verification; this is not notarization.

Measured duration of the broad application AirPlay call: **4.548 seconds**.
The following durations use the helper's own monotonic clock; they are one
observation, not production averages or a claimed improvement over earlier runs.

| Component | Seconds |
| --- | ---: |
| Load helper module and its imports | 0.168 |
| Discover the selected receiver | 0.013 |
| Open TCP connection | 0.007 |
| Verify HAP credentials | 0.129 |
| PTP setup and event-channel opening | 0.056 |
| RECORD activation | 0.008 |
| Create the remote-control stream | 0.787 |
| Insert queue item, set property/rate and initiate feedback | 0.021 |
| Accepted command to first receiver playing event | 3.309 |

The remaining roughly 0.05 seconds includes launcher/interpreter startup,
synchronous bookkeeping and delivery of the confirmation into Swift. The
helper's relative clock is not assumed to share the Swift clock origin. No
individual value is assigned to that residual without additional anchors.

The approximately 3.31-second receiver-loading interval and 0.79-second control
setup account for about 90% of this short-fixture AirPlay call. This does not
establish the same distribution for large movies, HDR or every network state.

The control-stream interval is a single awaited RTSP SETUP response, not a fixed
sleep. The observed event channel opened on its first attempt. Starting feedback
took about 0.000026 seconds; its two-second periodic interval does not block
startup. Now Playing metadata is scheduled after the first playing event and
cannot explain this preceding delay. Discovery was already only 13 ms.

Offline import-only checks made no receiver connection. Four later invocations
in the new observer location took 0.151 to 0.154 seconds to load the module;
the first took 0.759 seconds. New cache paths and bytecode compilation may affect
that first invocation; it is not evidence of a cold daily-app startup. These
checks plus the live 0.168-second span do not support rewriting pyatv or replacing
Python as the first optimization.

Most of the broad span is therefore not CPU work demonstrated to be wasteful.
Removing the wait for the playing event would only report success earlier;
it would not establish earlier picture or sound. Within the 3.309-second interval,
HTTP request arrival/transfer, receiver buffering and decode readiness remain
unattributed. Protocol/session reuse could avoid some setup on a later episode,
but the 0.787-second observation is not a demonstrated saving and does not remove
the required first connection. No permanent helper or speculative background
connection is proposed.

The one live observation passed sampled output and Stop/cache cleanup. Strict
onset remained inconclusive with video/audio sampling gaps. The observer's
argument identity, call count, return identity and exception propagation passed
an offline delegation test. The eight onset tests and capture-supervisor tests
passed unchanged. No timing threshold was relaxed and no release was built.

## HTTP delivery and receiver-loading observation

One further successful HLS observation used the same clip, helper observer and
protocol settings, adding four timing calls to a private copy of LocalHTTPServer.
The ordinary source tree and installed app remained unchanged. The copy records
connection/response start, chunk processing and response completion on the HTTP
queue, filtered separately for the receiver and local AVPlayer. No URLs, path
tokens, headers, credentials or device addresses enter its HTTP measurement log;
only generated rendition filenames, counts, relative identifiers and times do.

The instrumented server passed the existing strict Swift 6 HTTP regression suite,
including Range, sparse files over 4 GB, abandoned requests, keep-alive and
telemetry filtering. One initial app launch failed before creating a control
report or opening a playback capture: recompiling the diagnostic executable had
lost the existing library-validation entitlement. Signing it with the original
client entitlements restored the original configuration. An invalid-input launch
check then succeeded without discovery/playback, followed by the successful run.
The failed launch is preserved and is not counted as a playback attempt.

Passive packet capture on the routed interface was refused by the OS during a
port-zero access probe. No real stream packets were captured and no permissions
or system settings were changed. Consequently these are **server-side processing
completion times**, not TCP acknowledgements, receiver receipt or decode times.
Apple describes the [send completion](https://developer.apple.com/documentation/network/nwconnection/send(content:contentcontext:iscomplete:completion:))
as processing of sent content; it is not a presentation callback.

This run's accepted-to-playing interval was **4.097 seconds**, versus 3.309 seconds
in the prior detailed run. No optimization was applied; do not interpret the
difference as a regression or improvement from these individual observations.

| Timeline boundary | Seconds from Play |
| --- | ---: |
| Helper reports accepted command | 1.572 |
| First receiver connection reaches server | 1.646 |
| Master playlist response begins | 1.787 |
| First video fragment response begins | 2.347 |
| First video fragment processing completes | 3.854 |
| Second video fragment processing completes | 4.571 |
| Third video fragment processing completes | 5.268 |
| Receiver reports playing | 5.669 |

For chronology only, the accepted-to-playing window partitions into 0.215 seconds
before the master response, 0.560 seconds through the first video request,
2.921 seconds spanning the first three video responses, and 0.401 seconds after
the third completion. These windows are not independent causal stages: receiver
loading, transfer and rendering can overlap. They must not be named pure
network, pure buffering and pure decoding time respectively.

The first three video responses were 2,072,200, 2,141,837 and 2,081,421 bytes.
Their server-side spans were 1.507, 0.679 and 0.653 seconds. A fourth video response
was already in flight when playing was reported. Before that report, 21 responses
had completed processing, totaling 7,166,911 body bytes; all recorded completed
responses matched their expected byte counts. This is not proof that every byte
had reached the receiver at that instant.

The master, video and audio playlist responses took 0.000666, 0.002136 and
0.000774 seconds on the server. Yet the next video/audio playlist requests began
about 0.264 and 0.279 seconds after the preceding playlist request. The server
does not spend those intervals generating playlists. Possible causes include
receiver scheduling, transport/acknowledgement behavior and delivery delay.
Without packet acknowledgements or a controlled comparison, none is established.

The implementation sends file-response headers and body chunks separately. A
bounded future transport experiment could assess coalescing tiny responses or
latency options. Apple's [TCP options](https://developer.apple.com/documentation/network/nwprotocoltcp/options)
include disabling Nagle, and [batching](https://developer.apple.com/documentation/network/nwconnection/batch(_:))
can group sends. This establishes available APIs, **not** a diagnosis that Nagle
caused the observed pauses. No batching or TCP option was changed in this work.

The VOD writer currently requests six-second segments. Testing a shorter target
on an isolated, matched fixture is another hypothesis, not a promised saving:
the receiver may buffer by duration, bytes or segment count. Copy-only
segmentation also depends on existing keyframes; no new video encoding is allowed.
More files could increase preparation, validation and cache overhead.

Captured color-pattern samples occur before the playing notification, but lack
the fresh subtitle identifier at that point. The first identifiable tone sample
was at 5.936 seconds and the first fresh-caption picture sample at 6.479 seconds.
The unchanged strict onset report remains inconclusive because of the audio gap.
Do not conclude that the receiver must preload three segments, that it decoded
nothing before playing, or that all 0.401 seconds are decoder startup. An initial
unique marker in the synthetic video could improve future attribution without
depending on subtitle appearance; that measurement change is not implemented.

The approved digital capture is itself a workload on the receiver and link; no
capture-free comparison was made. Stop, runtime/cache cleanup and sampled output
passed. No observer or capture process remained. Only this short SDR fixture was
run; HDR, OCR and long-pause tests were not repeated.

## Directed header/read/body observation

After the maintainer confirmed the receiver was free and awake, one HLS
observation used the isolated detailed observer. The approved digital screen
source supplied a frame before fixture generation and playback. No alternative
capture input, camera, microphone, pairing or permission change was used.

Storage cleanup had removed the previous generated MKV. The standard 60-second
H.264/E-AC-3 fixture was regenerated and validated with the pinned bundled engine;
the explicit development encoder was used only to create that synthetic input.
Its SHA-256 is recorded privately. The first three video-response byte counts
match the earlier run, but that does not establish byte-identical media. This is
one new observation, not a matched speedup comparison or a production average.

The diagnostic copy adds timestamps at header submission/completion, file-read
begin/end and body submission. Existing chunk-processing marks complete the
sequence. HTTP bytes, chunk sizes, callback sequencing, TCP configuration,
segmentation, pyatv and production sources remain unchanged. The new observer
passed the strict HTTP suite and its logged event order was checked locally.
The native check app was rebuilt and signed with its existing local development
identity and client entitlements; the ordinary installed app was not replaced.

Seconds, measured server-side processing spans:

| Video response | Total | Header submission to processing | File reads | Body submission to processing |
| --- | ---: | ---: | ---: | ---: |
| First, 2,072,200 bytes | 1.141556 | 0.001188 | 0.000504 | 1.138792 |
| Second, 2,141,837 bytes | 0.445809 | 0.000204 | 0.000613 | 0.443397 |
| Third, 2,081,421 bytes | 0.427067 | 0.000179 | 0.000473 | 0.425054 |

The rows also contain about 1 to 2 ms of other bookkeeping and observer work.
For the first response, the first 1 MiB was queued 1.71 ms after response start
and processed at 117.00 ms. Its remaining 1,023,624 bytes were queued promptly
after the first callback, then took 1.023502 seconds to complete processing.
The earlier observer's 1.158-second first-block interval is therefore not a
demonstrated fixed cost before the first body submission. The longer wait moved
to a later block in this observation. No optimization was applied.

Across the first three video responses, 2.007242 of 2.014432 seconds were inside
body-submission-to-processing spans. Header spans totaled 1.57 ms and file-read
spans 1.59 ms. These callbacks can include network-stack backpressure, scheduling,
link behavior and receiver draining. They do not isolate wire transit, TCP ACKs,
receiver buffering or decoder work. The read spans include observer overhead;
their small values do not support targeting disk reads as this startup's
seconds-scale bottleneck.

The master, video and audio playlist processing spans were 1.18, 2.98 and
1.89 ms. This does not establish when the receiver received those bytes or why
it scheduled its next request. Combining small responses remains a hypothesis,
not a demonstrated fix for the longer video-body waits.

| Boundary | Seconds from explicit Play |
| --- | ---: |
| First receiver connection | 2.092816 |
| Accepted event delivered into the app | 2.094113 |
| Master response starts | 2.103667 |
| First video response starts | 2.601060 |
| First video response completes processing | 3.742616 |
| Third video response completes processing | 4.664447 |
| Fifth video response completes processing | 5.419216 |
| First receiver playing event | 5.765164 |

Accepted-to-playing was 3.671051 seconds. The receiver connection slightly
preceding delivery of the accepted event is not reversed causality: these are
asynchronously observed boundaries. By playing, 27 responses totaling 11,709,250
body bytes had completed server-side processing, including five video fragments;
the sixth was in flight. Consequently the 1.101 seconds after the third fragment
also includes further delivery and cannot isolate buffering or decoding. Neither this
run nor the earlier three-completion observation establishes a fixed preload
segment count.

Captured picture, sound and the fresh subtitle passed their sampled-output
checks. Exact continuous onset remains inconclusive with
`audioSamplingGapAtStartup`; that evaluator was not relaxed and the run was not
repeated. Stop, runtime cleanup and isolated-cache removal passed. The storage
guard then removed the generated MKV and retained reports, captions and frames.
The installed executable retained its recorded hash. Reports are under
`.build/startup-benchmark/live-http-detail-ebump7bc/`, including
`http-detailed-breakdown.json` and `http-detailed-chronology.json`.

No playback optimization is justified as proven by these observations. The next
question is the variable body-processing wait. A future, separately approved
matched experiment could assess capture/link contention before changing
transport, segmentation or session lifetime. An observation without digital
capture could compare HTTP/receiver timing, but could not verify picture or
sound. Do not repeat unrelated receiver tests or promise that the whole measured
wait can be removed.

## Matched capture and TCP attribution

The maintainer requested isolation of network, receiver and capture effects.
One bounded ABBA campaign used capture off, on, on, off with a fixed ten-second
separation. There were no retries and no HDR, OCR or long-pause expansion. The
native app, engine, protocol settings, chunk sizes and HLS preparation remained
unchanged; only the private diagnostic observer gained read-only counters and
body hashing.

The macOS SDK exposes `NWConnection.startDataTransferReport()` without packet
capture. Its collected interval reports provide transport byte counts,
retransmissions and RTT estimates. The installed SDK's `connection_report.h`
documents each counter's measurement interval; the Swift interface declares the
corresponding public fields. No BPF access, admin permission, network-settings
change or extra receiver app was needed. The observer passed the strict HTTP
suite. A local logging check received ten transport reports and independently
matched four full-segment SHA-256 values to the test input. An initial local
logging attempt had no output file, so no metrics could be assessed; that was
corrected before any new receiver observation.

One synthetic MKV was generated, validated and retained throughout all four
observations. Each case had an empty isolated HLS cache and the same five-second
pre-Play gate. Capture-on cases opened only the approved digital source. The
capture-free cases used a timed gate with no sampler process during playback;
they do not verify picture or sound. A preliminary source-readiness probe had
already closed before the fixed separation and the first measured startup.

The common fixture and diagnostic binary retained their hashes. Fifteen shared
initial media objects, including the first three video responses, matched
SHA-256 byte for byte across all four cases. Each subtitle used a fresh per-case
identifier to reject stale captured output; subtitle text was the declared
variation. Frame/OCR analysis ran after all four timed observations so it could
not load a subsequent startup.

Seconds, individual observations of this diagnostic app:

| Order | Digital capture | Play to receiver playing event | Accepted to playing event | First three video-body processing spans |
| --- | --- | ---: | ---: | ---: |
| 1 | Off | 4.449149 | 3.273701 | 1.995528 |
| 2 | On | 5.762535 | 3.343719 | 3.510609 |
| 3 | On | 5.811259 | 3.710478 | 3.676681 |
| 4 | Off | 4.564914 | 3.359205 | 1.982403 |

The descriptive central values of the two observations per mode were 4.507032
seconds without capture and 5.786897 with capture from Play to the receiver
event: an observed difference of 1.279865 seconds. Of that difference, 1.069219
seconds occurred before accepted-event delivery and 0.210646 seconds afterwards.
This is an exploratory matched comparison with two observations per mode, not a
production latency average, confidence interval or universal correction factor.
It does establish that the measurement arrangement can affect the observed
startup substantially; no playback optimization produced this difference.

The first three body-processing spans increased by 1.604679 seconds between
mode central values. Do not add that increase to the Play-to-playing difference:
the spans overlap other work. In both captured cases, the third fragment's
processing callback completed about 0.56 seconds after the first playing event.
Thus three fully processed fragments cannot be treated as a required preceding
startup gate, nor can processing completion be relabelled receiver receipt.

The TCP reports expose a real transport signal in both modes:

| Order | Capture | Sampled smoothed RTT, ms | Retransmitted bytes across first three video intervals | Retransmitted/sent counter ratio |
| --- | --- | --- | ---: | ---: |
| 1 | Off | 9 to 32 | 181,000 | 2.88% |
| 2 | On | 20 to 71 | 105,704 | 1.71% |
| 3 | On | 23 to 32 | 262,088 | 4.12% |
| 4 | Off | 17 to 37 | 315,664 | 4.89% |

These are interval counters and sampled RTT estimates, not packet-by-packet ACK
times or a measured radio loss percentage. TCP retransmission can accompany
loss, reordering or delayed feedback; it does not locate the physical cause.
The counters are not consistently higher with capture. Neither retransmitted
bytes divided by throughput nor summed RTTs can apportion startup seconds.
Link retries below TCP and receiver flow control also remain unobserved.

The receiver/control stages vary too. Control-stream SETUP took 29.7 and 48.1 ms
without capture, versus 825.7 and 90.8 ms with capture. Another captured run
instead spent longer in base setup and verification. The earlier 0.79-second
SETUP observation is not an established fixed cost to remove. Imports in this
new diagnostic location took 635 to 652 ms in all four cases; this does not
establish ordinary installed-app import latency or a capture-induced import cost.

Without capture, accepted-to-playing still took 3.274 and 3.359 seconds. Roughly
1.99 seconds lay inside the first three body-processing spans, but they include
sender scheduling, TCP backpressure, the link and receiver draining. Further
video deliveries also occur before the playing event. Internal buffering,
decoding and notification latency are not separately observable through these
counters. A numerical split of that remainder into pure network and pure Apple
TV time would be invented.

All four cases passed receiver controls, Stop and isolated-cache cleanup. Both
captured cases passed sampled picture, sound and fresh subtitles. Their strict
onset checks remained inconclusive with startup sampling gaps and, in one case,
no fresh moving fixture before the control boundary. No threshold was relaxed.
The storage guard removed the common MKV after the campaign, keeping reports
and frames. The installed app remained unchanged. Private evidence is under
`.build/startup-benchmark/live-attribution-abba-ag4c1z8n/`, particularly
`paired-breakdown.json` and `transport-and-helper-summary.json`.

A final read-only discovery matched the selected receiver, and the current route
used the Mac's `en0` Wi-Fi interface. This does not identify whether the Apple TV
itself uses Wi-Fi or Ethernet. No interface, router, VPN or radio setting changed.
The first standalone route probe lacked the packaged Python dependency path and
stopped at import, before discovery. Supplying the native helper's existing
dependency environment allowed the read-only inspection to complete; no engine
or dependency was replaced.

### Read-only link follow-up

A later, non-playback inspection read the Mac's current radio information:
802.11ax on channel 36, 5 GHz, 160 MHz, MCS 11, a reported 2,401 Mbit/s PHY
transmit rate, and signal/noise of -26/-92 dBm. This is a current snapshot,
not a recording taken during the four startups. PHY rate is not usable TCP
throughput. It does not suggest a weak Mac-side signal at that moment, but
cannot exclude interference, airtime contention, link retries or receiver-side
conditions. Interface counters reported zero input/output errors; these are not
TCP retransmission or Wi-Fi retry counters.

The retained interval data also disproves a simple retransmitted-byte-count
explanation: in the same captured observation, one video body-processing span
took 1.822527 seconds with 34,752 retransmitted bytes, while another took
0.885652 seconds with 227,336 retransmitted bytes. This does not rule out
retransmission timing as a contributor. It shows that retransmission volume
alone cannot explain or quantify the longer wait.

The selected receiver's own Wi-Fi-versus-Ethernet connection remains unobserved.
No MAC-address or AirPlay-advertisement heuristic is used to infer it. Apple's
[network settings guide](https://support.apple.com/en-ie/guide/tv/atvb00f5b993/tvos)
is the applicable device UI reference. The maintainer was asked to leave
Settings > Network visible for reading via the already approved digital source;
no playback or additional capture has been started for that pending check.

The default command-line tool selection lacked `devicectl`. A transient
`DEVELOPER_DIR` pointing at the installed Xcode allowed a device-list query,
which returned no CoreDevice devices. That query unexpectedly triggered
Xcode/CoreSimulator initialization, including an installation-success message;
the specific installed component was not identified. No further Xcode queries
were made. No receiver installation, pairing, network-setting change or global
developer-directory change was requested. This tool-side effect is distinct
from the application and network investigation results. Sanitized radio metrics
and the private device-list result remain under `.build/network-investigation/`.

The useful next boundary is transport reliability under this actual connection,
with capture-free HTTP/receiver timings as the baseline. Review link conditions
before choosing another bounded experiment; do not
infer a codec defect, change network settings automatically or repeat the
unchanged ABBA campaign. A precise decoder-versus-wire split would require new
receiver or packet-level evidence unavailable in this campaign.

## Where measurement is still incomplete

### Offline reassessment after storage cleanup

The archived HTTP records were reread and checked against the cleanup manifest's
SHA-256 values. This is a reassessment of the same successful observation, not a
new receiver run or a timing improvement. The first attempt at the analysis
expected three local-player video requests; only two exist in that recording.
The corrected analysis explicitly marks the third local request as unobserved.

| Receiver video response | Response processing | First 1 MiB processing boundary | Remaining chunks |
| --- | ---: | ---: | ---: |
| First | 1.507 s | 1.158 s from response start | 0.347 s |
| Second | 0.679 s | 0.266 s from response start | 0.304 s and 0.109 s |
| Third | 0.653 s | 0.332 s from response start | 0.320 s |

The first boundary includes header-send completion, file reading, body submission
and the first body-send completion. The observer did not distinguish these four
steps. It cannot attribute 1.158 seconds to disk access, TCP, receiver buffering
or decoding alone. These are local processing callbacks, not acknowledgements.

The first three playlists consumed only 3.58 ms of server processing in total.
The next playlist requests arrived 263 and 277 ms after the previous response
completed. The next two video requests followed their preceding completed video
responses by 37.5 and 44.3 ms. This distinguishes playlist sequencing from the
longer body-transfer spans without claiming a cause for either interval.

The local player processed the same first two video-file sizes in 1.96 and
1.21 ms. Local and receiver paths differ; this is not a link-capacity benchmark.
It does not support assuming an unavoidable, seconds-long local file-generation
cost for these already prepared files. Receiver-side processed-byte averages
were 11.0, 25.2 and 25.5 Mbit/s, not measured maximum network capacity.

That reassessment defined an observation with separate header queued/processed, file-read
begin/end and body queued/processed markers to an isolated diagnostic server.
Keep response bytes, chunk sizes, callback sequencing, TCP options, segmentation
and pyatv unchanged. One directed run can then distinguish work before body
submission from time awaiting its processing callback. It will still not reveal
internal decoder or buffer state. No transport optimization is justified yet,
and unrelated HDR, OCR, seeking and pause tests did not need repeating.

That observation-only source was prepared privately in
`.build/startup-http-detail-tools/`. It passes the strict Swift 6 HTTP regression
suite. With logging enabled, 11 local requests retained the expected event order
from response start through header processing, file reading, body submission and
chunk processing. The subsequently authorized directed observation above used
that source. The production server remains unchanged.

The ordinary HLS startup trace starts inside `beginStreaming`, after preceding
selection/authorization work, and ends at a receiver media request. The test
runner has a separate explicit Play anchor, after media analysis. Direct MP4
does not have an equivalent detailed stage trace. Consequently:

- Opening/analyzing a movie and pressing Play on an already analyzed movie are
  different journeys. Measure both, without adding analysis twice.
- Pre-Play authorization remains outside the Play anchor. One live observation
  attributes discovery/authentication/session/queue timings and another records
  HTTP response chronology. Wire receipt and the split between internal buffering,
  decoder startup and notification delay remain unverified, as does continuous
  output onset.
- PGS/VobSub OCR, HDR/DV direct MP4, HDR HLS, large real movies and external storage
  are not measured by these local fixtures.
- Continuous captured audio has a startup discontinuity. The diagnostic does
  not establish a long PNG write as its cause; retain the gap as unverified.

Any further device campaign needs a specific measurement change that addresses
the observed gap or explicitly reports interval-censored observations. Do not
repeat the unchanged three-run plan or relax its acceptance threshold. Record
separate positive-sample and confirmation times, without relabelling them onset.
Direct HDR, OCR and warm reuse need their own attributable output markers before
expanding the timing matrix; do not repeat unrelated long-pause or seek tests.

## Proposed improvements, not implemented

| Order | Work | Measured opportunity | Risk | Effort |
| --- | --- | --- | --- | --- |
| 1 | Assess capture/link contention with matched body-processing observations, without changing playback | Variable roughly one-second body wait; no removable fraction established | Low production risk; capture-free observations cannot verify picture/sound | Medium |
| 2 | A controlled tiny-response transport comparison, retaining exact bytes and HTTP semantics | About 0.56 s spans playlist/init acquisition in one run; headers themselves were processed in milliseconds | Low to medium; shared server still needs both routes and HTTP regressions | Medium |
| 3 | Assess moving cache admission outside the critical startup path | Store span about 0.36 s on this synthetic input; realizable gain unproven | Medium: ownership, cancellation, disk limits and eviction must remain correct | Medium |
| 4 | Profile warm checkout and remove proven redundant filesystem work | About 0.73 s in checkout; cannot remove integrity checks to claim that saving | Medium | Medium |
| 5 | Measure independent text extraction, then assess immutable text reuse | Unknown; the current subtitle span cannot quantify it | Medium: identity, timing and track invalidation | Medium |
| 6 | Consider bounded session reuse between episodes, without a permanent helper | Control setup costs 0.79 s in one observation; potential saving unproven and first setup still required | High: authorization, session ownership and receiver compatibility | Large |

Shorter copy-only HLS fragments are a separate, higher-scope experiment if delivery
and receiver demand still dominate after the transport comparison. Do not change
transport, segmentation and session reuse together, or subtract entire observed
windows as a predicted saving.

Do not prioritize rewriting basic analysis: it costs roughly 11 ms on these two
inputs. Do not disable cache globally: it helps reuse but has a first-use cost.
Changing codecs, transcoding video or starting partial HLS is outside this work.

## Evidence identity

Private reports originally lived under ignored `.build/startup-benchmark/`.
The storage cleanup moved them, with their original relative paths, into
`.build/retained-reports-20261019/reports-and-diagnostic-sources.tar.gz`.
Its adjacent `cleanup-manifest.json` records the archived file hashes. Generated
media and obsolete binaries were removed; reports and diagnostic sources remain.
The following names identify the original run directories inside that archive:

- `measurement-f3qo4ykc`: 30 short preparation samples, probe calls, compiler
  entry points and production-source/engine hashes.
- `measurement-large-f2ay93a7`: nine large preparation samples and parity records.
- `live-20261019-r48lxk9c`: original-sampler live run and inconclusive timing.
- `live-20261019-ypz9dpvo`: instrumented-sampler live run and inconclusive timing.
- `live-20261019-f7eu470d`: one timing-observer run, private stage markers,
  stage breakdown, passed output and inconclusive onset. Observer and delegation
  checks remain under ignored `.build/startup-airplay-stages/`.
- `live-20261019-8ifjc0qr`: failed diagnostic launch before playback, with no
  HTTP records or control report.
- `live-20261019-3bv5sa5_`: successful HTTP-observer run, detailed server/helper
  chronology, passed output and inconclusive onset. Build, focused HTTP tests and
  the observation-only source diff remain in `.build/startup-http-observer/`.

The first live wrapper attempted to rewrite its exclusive-create summary and
failed after the completed assessment. The case controls, capture and timing
files were already retained and unchanged. The wrapper was corrected to keep
per-case results separate from the one final summary; this reporting error is
not attributed to playback. The first run is not counted as a wrapper success.

Summary SHA-256 values:

- Short: `368ffe4bb7284daacca14d0d7768c14a62b69a5b6999ea4b4ecddfa071a25977`.
- Large: `95559c6bf2ccafdd5d6aa182625adcca8dfea5151299e8f68d433af98d82410e`.
- Source/engine identity: `ccbbc4fd4b156fe963eff2dd5e5c9c61fe42eef67eb54753d8e6c9c987fc99cc`.
- First live strict timing: `0dc235bc6ca63f4facec83f8e9618d41440e5b224c19e06c6da6b2346de3addc`.
- Diagnostic live strict timing: `110fd8cf791fea50836ce532077f62f1ca67734c4258ce738fd26cf877d84cc3`.
- Separate live observation summary: `fbf999517cde3d768b3f4924c6a0c181e8b92842fc7a103acf26f48cc7141a29`.

No media names, device identifiers, capture frames or credentials are published.

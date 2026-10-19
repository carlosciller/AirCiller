# HLS subtitle recovery after seeking

## Selected scope

19 October 2026. Investigate the remaining HLS visibility gap documented in
[external PGS](EXTERNAL_PGS.md#hls-seek-investigation). Only the HLS WebVTT writer
changes. Direct MP4, video/audio packaging, shared controls, transport, engines
and source subtitles are unchanged. Session subtitle files are regenerated;
prepared base-media cache entries do not contain these files.

Validation: deterministic WebVTT regressions, one final strict local gate and a
focused captured HLS seek case using the unchanged long-cue input. Retain earlier
direct MP4, codec, OCR, long-pause and cache evidence: their relevant boundaries
are not changed. Do not repeat those matrices for this repair.

## Diagnosis

The previous work already rejected a single subtitle segment, stable cue IDs
and alternative equivalent timestamp-map anchors. Repeating those experiments
was not selected.

Three new bounded comparisons used the same candidate and HLS video, with
simultaneous top and bottom captions and isolated seeks to 15, 2 and 88 seconds.
The original visible intervals were 0 to 90 seconds. Approved digital Apple TV
capture, receiver controls and cleanup completed; no camera or microphone was
opened. The installed application was unchanged.

1. Two held captions disappeared after the forward seek and returned together
   in the first sample 5.485 seconds after resume. They were already above and
   below the controls, so simple visual overlap does not explain the gap.
   Both remained visible after the backward seek even with controls open.
2. Keeping the top caption held and renewing the bottom caption every second
   restored both in the first forward-seek sample, 0.278 seconds after resume.
   That diagnostic changed the bottom text each second and was not a proposed
   production change.
3. Repeating the comparison with identical bottom text restored both in the
   first sample, 0.263 seconds after forward resume, while controls were visible.
   Captions were absent after their declared end. No text change was required.

These observations isolate a receiver presentation refresh issue for already
active cues. They do not expose or prove a particular private tvOS implementation.
First-sample figures are bounded observations, not frame-accurate latency or
general performance guarantees. Original private captures and reports remain
under `.build/playback-checks/subtitle-seek-controls-*`; none is rewritten as a
production acceptance run.

## Repair and preservation

The HLS writer expresses ordinary captions as contiguous intervals of at most
one second, retaining identical payload and positioning/settings. The complete
displayed interval is unchanged, including fractional starts/ends, simultaneous
captions and subtitle delay. Prepared cue starts remain ordered; ties retain
source order. Each prepared interval is repeated in full in every overlapping
HLS segment. It is not clipped at the segment boundary.

Only overlaps for the current video segment are materialized. Cancellation is
checked during renewal, and a nonadvancing interval is rejected. No fake text,
invisible refresh caption, extra seek, pause, track toggle or burned-in subtitle
is introduced. Video and audio remain untouched.

WebVTT payloads with internal timestamp tags are left intact: splitting their
outer interval could change timestamp semantics. Immediate post-seek recovery
for those specialized cues remains unverified.

The added regression fails the original writer. Coverage checks require exactly
the expected intervals and unchanged styled payloads, repeated boundary-crossing
intervals, ordering for overlapping positions, fractional tails, negative delay
and preservation of internal timestamp tags. Existing golden outputs are updated
to the new representation without dropping their exact-output assertions.

The pull-request handoff records final candidate outcomes separately; these
diagnostic experiments are not release acceptance.

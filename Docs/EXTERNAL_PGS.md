# External PGS subtitles

The candidate accepts Blu-ray PGS `.sup` files through Add Subtitle File and sidecar discovery. A sidecar shares the movie's base name, optionally followed by a language or other suffix. PGS contains one subtitle stream; the original filename, inferred language, forced and SDH labels remain available in the track picker.

Recognition starts only when the selected subtitle is prepared for playback. The existing Apple Vision OCR produces selectable WebVTT for HLS or a temporary text track for direct HDR MP4. Neither video command builder changes. The source movie and `.sup` remain untouched; no engine or dependency is added. Recognition and styling have the same limitations as embedded bitmap subtitles.

## Input and cache boundaries

External bitmap input currently requires `.sup`, the PGS codec, stream zero and the `PG` signature. Missing and malformed files are rejected before OCR. This initial format check is followed by FFmpeg validation during decoding.

The OCR cache identifies the subtitle file by path, size and modification time, plus language and movie duration. Two sidecars must not share the movie's embedded-track cache entry. A different movie duration also needs a distinct entry because the last bitmap may have no explicit clearing event. Existing embedded cache identities remain unchanged.

Raw PGS clocks are preserved with `-copyts`. An external file does not inherit the movie container's transport-stream origin. Existing embedded TS normalization is unchanged.

## Validation, 8 September 2026

Deterministic checks cover external track metadata and identity, changed source files, different durations, malformed and missing input, and acceptance by the isolated playback runner. Existing text subtitles remain selectable.

A private `.sup` extracted from a known PGS fixture was shifted by five seconds for a local timing test. Its composition records independently declare the first visible state at 5.000 seconds and a clear at 7.002 seconds. Direct text materialization and HLS WebVTT matched both times within 2 ms using the pinned engine and local Vision. The movie used a separate TS clock offset, which was not applied to the external subtitle.

The first test expectation incorrectly treated an intermediate composition update as a clear; inspection of the PGS records corrected that expectation. A subsequent four-frame test truncated before the clearing event. The passing test retains eight frames, as the existing bitmap timing fixture does. Neither unsuccessful test is recorded as passed. Sandboxed Vision pixel-buffer creation was unavailable; local OCR ran outside that restriction without opening a camera or microphone.

The complete strict suite finished with `AirCiller local checks: OK`. The candidate measures 153,926,061 logical bytes, 1,110 bytes above the installed 0.12.4 local build. A separate real probe discovered a matching uppercase `.SUP` sidecar and excluded an unrelated file.

The native interface accepted a `.sup` file, listed its original filename and language, and displayed the local-OCR notice and cache explanation when selected. No playback was started. The existing modal file picker dismisses the track popover, so the panel was reopened to select the newly attached track. This interaction can be polished separately. Cancelling retained the previous active subtitle; the candidate was then closed.

## Physical Apple TV output, 8 September 2026

The isolated check app exercised external attachment, original audio, playback, pause/resume, a rapid seek sequence, receiver destination and cleanup. Capture used only the approved Apple TV screen/audio source. No camera or microphone, interactive password prompt or installed-app replacement was needed.

| Input and route | Captured playback frames | Moving frames | Non-silent audio samples | Subtitle observation |
| --- | ---: | ---: | ---: | --- |
| PGS, direct HDR, 90-second cue | 18 | 17 | 30 / 46 | Matched the source bitmap before and after seeking |
| PGS, HLS, 90-second cue | 18 | 18 | 40 / 46 | Correct initially; absent after seeking within the cue |
| PGS, HLS, cues lasting 3 to 6 seconds | 19 | 19 | 41 / 48 | Matched the source bitmap before and after seeking |
| SRT comparison, HLS, 90-second cue | 18 | 18 | 35 / 47 | Same post-seek disappearance as the long PGS cue |

The bitmap test fixtures reuse an original subtitle image with controlled presentation and clear events. Captured frames were compared with that source image, including the stable post-seek window near second 16. The long PGS cue's cached WebVTT retained the full interval from 0 to 90 seconds. The SRT comparison bypasses OCR and reproduces the same visible gap, so the failure is not specific to external PGS recognition. Its precise cause is not established.

The raw automation reports confirm controls, sampled motion and digital audio only; subtitle acceptance comes from the separate captured-image review. No report claiming all cases passed has replaced those reports. These short checks do not establish physical speaker routing, HDR presentation, frame-accurate television timing, behavior after the observed window or whole-film reliability.

**Release follow-up:** the initial HLS long-cue failure prompted the isolated diagnosis and control correction recorded below. [RFC 8216 section 3.5](https://www.rfc-editor.org/rfc/rfc8216.html#section-3.5) requires complete cue intervals across WebVTT segments. The correction leaves those intervals and both packagers unchanged.

The daily-use 0.12.4 executable is unchanged. No version bump, release or installed-app replacement is included in this candidate. All test and capture processes ended.

External VobSub `.idx`/`.sub` remains a separate follow-up.

## HLS seek investigation

Three isolated experiments repeated the same 90-second SRT case on Apple TV: one complete VOD subtitle segment, stable cue identifiers across the original segments, and equivalent per-segment timestamp-map anchors. Each compiled and passed receiver control, sampled motion/audio and cleanup checks. None restored the subtitle in the captured post-seek window. The single-segment variant also lacked the subtitle in the reviewed initial frame. All experimental playback-source changes were removed; they are not included in this candidate.

The stable-identifier capture retained the caption after the first pause/resume and before the seek sequence. This narrowed the failure to the later sequence but did not distinguish a single seek from rapid forward/backward seeks. The subsequent checks below address that distinction. No full application check or subtitle acceptance is claimed for the rejected experiments.

## Seek-burst correction

A later check on unchanged playback source isolated single seeks to seconds 15, 2 and 88. The 90-second SRT cue returned after the forward seek, remained visible after going back and was absent after its declared end. The forward-seek capture showed a short gap followed by recovery around the dismissal of the receiver's transport controls. This is correlation, not proof of an internal tvOS cause.

Repeating the original rapid forward/backward sequence with eight seconds of observation produced a different result: the long SRT and PGS cues were still missing after the controls disappeared. Separate local image analysis retained those failures and distinguished early missing frames from later recovery.

`AirPlaySeekCoalescer` now replaces queued seek destinations during a 300 ms burst and sends only the final one. The Mac timeline updates immediately. Pause and Resume flush a pending destination first; Stop, terminal events and session replacement cancel it. Existing request IDs and receiver reconciliation remain in use. Both media packagers, the WebVTT writer, original movies, source subtitles and bundled engines are unchanged. This handles commands originating in AirCiller; it does not intercept seeks made directly by a physical Apple TV or iPhone remote.

Local regression checks cover final-destination selection, explicit flush, cancellation, session replacement, failed sends, cancelled deadlines and automatic dispatch. The complete strict suite passed after the correction. Physical follow-up used the shared control change separately with HLS and direct HDR; bounded results and the remaining transient visibility gap are retained in the private evidence record. No installed app was replaced or release published.

| Corrected candidate | Playback / moving frames | Non-silent audio samples | Late subtitle check |
| --- | ---: | ---: | --- |
| HLS, long SRT cue, repeat | 30 / 29 | 59 / 74 | Present in all 3 sampled late frames |
| HLS, long PGS cue | 27 / 26 | 66 / 76 | Present in all 3 sampled late frames |
| Direct HDR, long PGS cue | 29 / 26 | 43 / 74 | Present in all 4 sampled late frames |

Each case passed receiver position, one acknowledgement for the four-input burst, pause/resume and cleanup. The late assessment examines frames six seconds after the resumed event and does not hide the missing earlier frames. An initial corrected SRT capture showed recovery but retained only one late frame, below the two-frame minimum; its assessment remains incomplete. The table uses a separate repeat with adequate coverage. Original control and capture reports were not rewritten.

These results validate recovery after Mac-originated seek bursts, not uninterrupted subtitle visibility during seeking. The short HLS gap remains, while the direct HDR sample retained its caption through the observed transition. Physical remote-originated bursts and whole-movie reliability remain outside these checks.

## Local installation

The maintainer authorized installation on 8 September 2026 after reviewing those results and limits. The exact normal candidate produced by the passing strict suite replaced the closed daily-use app. Its local signature and unchanged credential-service executable were verified before and after the move. The previous app remains the active rollback copy; the older rollback was preserved in the local archive. The candidate was opened without starting playback. No GitHub release or appcast was published; the development candidate retains version 0.12.4 (build 57).

This work is included in the 0.12.5 release candidate together with [external VobSub](EXTERNAL_VOBSUB.md). The installation above records the earlier local PGS build; it is not the 0.12.5 distribution record.

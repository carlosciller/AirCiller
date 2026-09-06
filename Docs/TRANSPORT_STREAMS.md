# Transport streams, part 1

Introduced in 0.12.3. Local preparation checks, the four-case Apple TV batch and the subsequent corrected bitmap-subtitle checks passed on 6 September 2026. The failed observations and their corrections are retained below. Packaging and signed-update checks are separate release steps.

## Scope

Open individual, complete, unencrypted TS, MTS and M2TS files containing a single program. H.264 and HEVC use the existing video-copy paths. Original audio remains the default; unsupported audio still requires explicit conversion approval.

This does not add disc menus, Blu-ray playlists, automatic joining of split recordings, encrypted media, live transport URLs or selection between several broadcast programs. MPEG-2 video remains unsupported. AAC-LATM, MP2, DTS, TrueHD and Blu-ray PCM are not newly accepted as original audio. PGS and other subtitle limitations remain as documented in [Compatibility](../COMPATIBILITY.md).

## Changes

- One file-type definition serves opening, Playlist admission and the isolated check app. Finder declares the same extensions. Matching is case-insensitive; remote URLs are rejected.
- The probe rejects multi-program transport streams instead of potentially selecting video and audio from different programs. A transport file with no usable duration is also rejected with an explanation.
- HLS explicitly adapts ADTS-framed AAC to the MP4 audio configuration. The AAC payload is copied, not encoded. FFmpeg did not automatically apply this step inside the HLS/fMP4 muxer in the failing fixture. See [FFmpeg's filter documentation](https://www.ffmpeg.org/ffmpeg-bitstream-filters.html#aac_005fadtstoasc).
- The direct MP4 packager, HDR configuration handling, playback control, authorization and pinned engines are unchanged.
- Bitmap extraction retains the TS source clock until it can be aligned to the video's start. Canvas dimensions are read from the root stream, without counting the duplicate program entry. Cached OCR from the previous extraction version is regenerated on demand.

## Review corrections

The original receiver batch used external SRT and did not cover embedded PGS. A copy-only M2TS fixture with a one-hour clock offset exposed a roughly 0.9-second early first cue. Preserving absolute timestamps and subtracting the video's start in the bitmap filter restores the source-relative time. Adding `-start_at_zero` alone did not solve it. Video packagers are unchanged.

The complete conversion also exposed duplicated CSV dimensions from the TS program and root stream. Reading the root JSON stream fixes the canvas lookup. The capture preflight now explicitly requests program information before rejecting multi-program files; a real two-program TS is rejected with the pinned probe before audio checks or playback.

`BitmapTimelineSmokeTest` checks finite, missing, zero and negative TS origins and preserves non-TS behavior in the deterministic suite. Its optional real-media mode takes a fixture and independently known first-cue start/end times. Both direct-track and HLS subtitle materialization matched the packet-clock reference within 2 ms for the offset M2TS, a first cue delayed to 30.901 seconds, and the baseline MKV. These are local timing assertions, not captured-output synchronization measurements. Apple Vision requires an ordinary local execution environment for these media checks; sandboxed pixel-buffer creation failed and was not counted as a pass.

The first focused receiver follow-up passed motion, digital audio and controls for HLS and direct HDR, but its captured frames did not show the expected embedded PGS cues. The report remains a failed subtitle observation. Both M2TS subtitle streams lacked the language tags present in the MKV reference; their generated WebVTT contained the correct text and cue times.

The follow-up resolves missing bitmap-language metadata from already-recognized text using Apple's on-device Natural Language framework. It requires at least 40 letters and a language hypothesis of 0.9 or greater, preserves declared languages and track identity, and labels inferred metadata. Short or uncertain text remains undetermined. No source file, audio or video is changed. Deterministic tests cover inference, declared-language preservation, short text, note-only input and text-track exclusion.

The corrected candidate then passed the same two M2TS fixtures without adding language tags to the inputs. Captures showed the expected PGS text and brackets in both HLS and direct HDR, compared with decoded source bitmaps. HLS supplied 19 playback-window frames with motion and 41 non-silent audio measurements out of 47; direct HDR supplied 19 frames with 18 central-image changes and 32 non-silent audio measurements out of 47. Both control reports passed progress, pause/resume, rapid seeks, Stop and cleanup. The strict local suite passed before the isolated candidate was rebuilt. This is sampled digital output, not frame-accurate synchronization, physical HDR/speaker certification or whole-movie testing.

## Local evidence, 6 September 2026

| Fixture | Preparation | Result |
| --- | --- | --- |
| H.264 / E-AC-3, TS | Separate HLS/fMP4 | Complete VOD; encoded picture and audio match |
| H.264 / E-AC-3, MTS with 192-byte packets and a one-hour clock offset | Separate HLS/fMP4 | Clock rebased; one-minute duration; encoded picture and audio match |
| HEVC / E-AC-3, HDR M2TS with 192-byte packets | Direct MP4 with selectable text | HDR metadata and text track retained; encoded picture and audio match |
| H.264 / AAC, TS | Separate HLS/fMP4 | Reproduced the missing ADTS adaptation, then passed with unchanged AAC payload |
| H.264 / AAC, existing MP4-style input | Separate HLS/fMP4 | Regression passes with unchanged AAC payload |
| HEVC / E-AC-3, HDR M2TS | Multiplexed HLS/fMP4 without subtitles | HDR header preparation passes; encoded picture and audio match |
| HEVC / AAC 5.1, HDR M2TS | Multiplexed HLS/fMP4 without subtitles | AAC framing adaptation passes with all six channels and encoded payload intact |
| HEVC / AAC stereo, synthetic PQ test pattern in M2TS | Multiplexed HLS/fMP4 without subtitles | Complete VOD, static HDR header and unchanged encoded payloads |

Fixtures are approximately 60 seconds. Video comparison normalizes Annex B framing and repeated parameter sets, then hashes coded picture NAL units and any Dolby Vision RPU units. Audio is compared after normalization to ADTS, AC-3 or E-AC-3 elementary framing. Stream properties, durations and near-zero output start times are also checked. Separate HLS renditions retain the existing roughly 62 to 78 ms difference in relative stream starts for these fixtures; direct MP4 and multiplexed HDR HLS retain their relative start exactly. These checks do not establish frame-accurate synchronization or physical output.

The default ffprobe window omitted the AAC profile on the multiplexed 5.1 fixture. The verifier now uses an explicit, bounded 10-second/32 MB probe and still requires matching profiles; it does not ignore a missing value. The synthetic HDR check initially rejected an input without declared PQ transfer. Its corrected fixture declares PQ in the HEVC stream before it is supplied to AirCiller. Neither adjustment changes the production probe or packagers.

The M2TS probe identifies the HDR fixture as HEVC/PQ, not as a Dolby Vision configuration. Preserving RPU bytes alone is not proof of Dolby Vision signaling at the receiver. Do not advertise general Dolby Vision transport-stream support from this test.

Deterministic coverage includes file admission, Finder registration, multi-program and missing-duration rejection, explicit audio conversion boundaries, the AAC framing condition and the copy verifier's detection of altered pictures or dropped RPU units.

The complete strict Swift 6 suite passed again with `AirCiller local checks: OK` after adding HDR-without-subtitles runner coverage. The isolated check app was rebuilt, and its bundled engine accepted all four transport fixtures through the capture workflow's local preparation checks. No receiver, camera or microphone was opened. The installed executable's checksum is unchanged.

## Reproduce local preparation

With the pinned engine bootstrapped, provide a short fixture and a new output directory:

```sh
zsh Scripts/check_transport_stream.sh /absolute/path/sample.ts /absolute/path/new-output
```

The command compiles the focused harness, uses the real probe and command builders, and verifies encoded payload preservation. Add `--hdr-hls` to test HDR without subtitles instead of direct MP4. The packaging child has a 120-second watchdog. The command does not launch the app, contact a receiver or capture anything. For a batch, compile once with this command, then reuse `.build/tests/transport-stream-packaging` and `Scripts/verify_stream_copy.py` with the pinned engine bin directory as their third argument. Keep fixtures and output outside Git.

## Apple TV acceptance

Use the existing [capture workflow](PLAYBACK_CHECKS.md) with `fixtureOverrides` in its private configuration. The default three-case batch is unchanged; part 1 explicitly adds `hlsHDRNoSubtitles` to its `cases` list. Overrides are limited to these four control cases:

```json
"fixtureOverrides": {
  "directHDR": "/absolute/path/hevc-hdr.m2ts",
  "hlsSubtitles": "/absolute/path/h264-aac.ts",
  "hlsNoSubtitles": "/absolute/path/h264-offset.mts",
  "hlsHDRNoSubtitles": "/absolute/path/hevc-pq-pattern-aac.m2ts"
}
```

All paths must be local files, with the usual size, duration, codec and audible-interval checks. Overrides replace fixture generation for those cases; they do not bypass the app or the exact Apple TV capture-source guard. The workflow generates fresh selectable text cues, exercises controls, captures sampled motion/audio/text and records each outcome separately. It never falls back to a camera or microphone.

The extra HDR case uses the real app's multiplexed HLS route, requires no subtitle selection, and verifies `video.m3u8`. Its captured output must contain the synthetic color pattern and no subtitle cues, as well as motion and audio. An arbitrary HDR movie is not a suitable fixture for this pattern check. A supplied SDR or direct-MP4 result cannot satisfy this case.

Run the selected batch only when the Apple TV is available and authorized. Missing or failed capture remains unverified. Do not repeat the long-pause or full stability matrix for this container-specific change without an additional reason. Release, version bump and installation remain separate decisions after acceptance.

## Apple TV results, 6 September 2026

The isolated candidate completed all four cases in one invocation with `sampled_output_observed` and no evidence gaps. Each case passed receiver progress, explicit pause/resume, rapid seeks and destination, media requests, Stop and cleanup. The approved Apple TV source supplied the following sampled digital output:

| Input and playback route | Playback-window frames | Fresh subtitle cue | Non-silent audio measurements |
| --- | --- | --- | --- |
| HEVC / E-AC-3 HDR M2TS, direct MP4 | 17, with 16 central-image changes | 17 of 17 | 34 of 46 |
| H.264 / AAC TS, HLS with subtitles | 16, all with central-image changes | 15 of 16 | 41 of 48 |
| H.264 / E-AC-3 offset MTS, HLS without subtitles | 17, all with central-image changes | None in 17 frames | 41 of 46 |
| HEVC / AAC HDR M2TS, multiplexed HLS without subtitles | 19, with 18 central-image changes | None in 19 frames | 41 of 49 |

The three synthetic cases also contained the expected color pattern. Representative saved frames from all four cases were inspected. Counts include playback, pause and seeking; they are not whole-stream quality percentages. Original audio remained selected, and the local elementary-stream comparisons above established copy-only preparation.

The initial invocation stopped before playback with `captureNotReady`: the exact source was available, but delivered no first frame. An isolated capture likewise produced no samples. A bounded diagnostic with the previously working MP4 fixture then received image and audio and passed receiver controls. After that diagnostic, the unchanged four-case workflow passed with its original readiness gate and evidence requirements. The first failed report and separate diagnostic remain preserved. This does not establish the cause or a permanent fix for capture startup from an inactive receiver; that QA issue remains a separate follow-up.

The candidate and capture-tool hashes are recorded with the private report. No password or viewing confirmation was requested during the successful batch. All owned test processes finished, and the installed app and stable credential-service executables were unchanged. No Mac or iPhone camera or microphone was opened. Captured frames, local source paths and device identifiers remain outside Git.

This validates the bounded transport-stream cases, not general Dolby Vision signaling from TS, physical HDR rendering, Atmos or speaker layout, physical remote buttons, frame-accurate subtitle synchronization or uninterrupted whole-movie playback. No installation, release or engine upgrade was performed.

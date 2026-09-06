# Original FLAC audio

## Scope

Version 0.12.4 accepts FLAC soundtracks whose channel layouts survive the existing fMP4 packaging. It adds the `fLaC` codec identifier to HLS manifests. The two FFmpeg command builders, pinned engines, AirPlay helper and credential component are unchanged. The app continues to copy video and original audio; it does not add a transcoded fallback track.

Apple documents FLAC stereo and multichannel audio in [HLS/fMP4](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices/). Receiver evidence below is separate from that specification.

## Channel-layout boundary

The pinned FFmpeg MP4 writer stores FLAC STREAMINFO, not additional channel-mask overrides carried by Matroska. A synthetic rear-channel `5.1` input retained every encoded audio frame but was reported as `5.1(side)` after remuxing. This failed validation. The app now rejects such reinterpretation before preparing media, explains the layout limitation and leaves conversion subject to explicit approval.

Eligibility requires a known native layout: mono, stereo, 3.0, quad, 5.0(side), 5.1(side), 6.1 or 7.1, matching its channel count. This list is a packaging prerequisite, not a claim that every receiver and speaker setup has been tested. Unknown layouts remain unsupported for original output.

## Local evidence

Six copy-only fixture checks passed: H.264 with mono, stereo and 24-bit 5.1(side) FLAC through separate HLS; HEVC HDR with stereo and 24-bit 5.1(side) FLAC plus text subtitles through direct MP4; and HEVC HDR with 5.1(side) FLAC through multiplexed HLS without subtitles. Fixtures use 48 kHz audio.

The verifier compares ordered encoded FLAC frame hashes and sizes, coded video including Dolby Vision RPU, channel count and layout, sample rate, bit depth, duration and relative start times. Container-generated FLAC metadata blocks are not encoded audio frames. Per-stream packet timing supplies duration when Matroska omits it; another track's lead-in must not be mistaken for audio duration.

Regression tests reject changed, missing and reordered FLAC frames, invalid packet timing and unsafe channel layouts. They check original HLS codec declarations with and without subtitles, mono and multichannel declarations, and explicitly selected audio conversion modes. Capture preflight accepts FLAC while still requiring audible test intervals. The bundle-size check measures logical bytes without following symlinks and rejects oversized builds.

## Apple TV output, 6 September 2026

The first capture attempt returned no initial frame and stopped before playback. A separate known-good receiver diagnostic passed controls without audiovisual capture. The repeated FLAC batch then passed unchanged. The failed report remains preserved; this is not a fix for inactive-receiver capture startup.

| FLAC input and route | Playback frames | Frames with requested subtitle | Non-silent digital audio samples |
| --- | ---: | ---: | ---: |
| Stereo, HLS with subtitles | 18 | 17 | 42 / 47 |
| Stereo, HLS without subtitles | 18 | 0 | 41 / 47 |
| Stereo, direct HDR with subtitles | 17 | 17 | 40 / 46 |
| 5.1(side), HLS with subtitles | 19 | 19 | 43 / 48 |
| 5.1(side), HLS without subtitles | 18 | 0 | 42 / 47 |
| 5.1(side), direct HDR with subtitles | 21 | 21 | 42 / 54 |
| 5.1(side), HDR HLS without subtitles | 18 | 0 | 43 / 47 |

All seven cases passed separate receiver controls and sampled-output checks: media requests, receiver progress, pause/resume, rapid seek acknowledgements, destination and cleanup. Captured HLS picture matched its generated pattern; subtitle cases required a fresh cue identifier. Representative saved frames were inspected. Source media, private reports and capture identities remain outside Git.

These tests confirm sampled picture, digital audio and subtitle output, not individual physical speaker channels, losslessness after the receiver's output processing, physical HDR rendering or whole-movie reliability. Native FLAC frames and channel labels are verified before transmission. No Mac or iPhone camera or microphone was opened. No interactive password prompt was needed, and all owned capture and test processes ended.

## Size and release checks

The local candidate before release metadata measured 153,924,893 logical bytes, 1,347 bytes above the 0.12.3 baseline. The ordinary app does not include the test runner. FFmpeg, Python and third-party packages were not upgraded or removed. Final package size, signature, CI and update installation are separate distribution checks.

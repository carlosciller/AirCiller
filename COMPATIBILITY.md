# Playback compatibility

This table describes AirCiller 0.17.0, not every format the bundled FFmpeg build can read. The Apple TV, television, audio equipment and local network also affect playback.

| Source | AirCiller behavior |
| --- | --- |
| MKV, MP4, M4V and MOV with H.264 or HEVC | Prepares a stream without encoding the video |
| Complete, unencrypted TS, MTS and M2TS with one program | Copies compatible H.264/HEVC and original audio; no disc menus, split-recording joining or live URLs |
| HDR and Dolby Vision | Preserves compatible video and metadata. Dolby Vision Profile 8.1 has been physically tested; other profiles are not universally guaranteed |
| AAC, AC-3, E-AC-3 and ALAC | Offered as original audio; the receiver must accept the channel layout and profile |
| FLAC soundtracks with a preserved channel layout | Original audio in HLS/fMP4 and direct HDR MP4; stereo and 5.1 have captured Apple TV evidence |
| Atmos carried by compatible E-AC-3 | Preserves the original stream; the playback chain determines Atmos output |
| PCM/LPCM with a supported integer precision and channel layout | Explicit lossless conversion to FLAC on HLS, with manual audio timing at zero; not original-audio passthrough |
| TrueHD with supported 24-bit precision, rate and channel layout | Explicit lossless conversion to FLAC on HLS, with manual audio timing at zero; Atmos objects are not retained |
| DTS and other unsupported original audio | Requires an explicitly approved audio conversion; DTS-HD MA lossless conversion is unavailable |
| SRT, WebVTT, ASS/SSA and embedded MP4 text | Selectable text with adjustable timing |
| Embedded Blu-ray PGS and DVD VobSub, external `.sup` and `.idx`/`.sub` pairs | Local Apple Vision OCR produces selectable text; preparation takes longer and recognition can be imperfect |

FLAC is supported as a movie soundtrack, not as a standalone music-file player. The current packager cannot retain some channel-mask overrides, such as a rear-channel `5.1` layout that becomes `5.1(side)` in fMP4. AirCiller explains the limitation and requires another track or explicit conversion approval. The [FLAC validation record](Docs/FLAC_AUDIO.md) lists tested cases and remaining limits.

## Subtitle appearance

HLS retains basic ASS/SSA formatting, alignment and positioning in WebVTT. Karaoke, animation, drawings and elaborate effects are simplified. The direct HDR MP4 route uses simpler styling. Apple TV controls the final presentation.

OCR preserves timing and approximate position, but does not reproduce the original bitmap or guarantee perfect text. Nothing is burned into the video.

Missing bitmap-subtitle language labels can be identified locally from the recognized text. Declared languages are preserved. Short or uncertain text stays undetermined and may not enable automatically on Apple TV.

Add external text or bitmap files from the tracks panel, or place matching files beside the movie. VobSub needs both files with the same base name in the same folder; choose either half to add all populated tracks. The supported index is VobSub v7 with a valid canvas and palette, up to 4 MiB for the index and 256 MiB for its bitmap companion. A text-format `.sub` file is not a VobSub bitmap. See the [external VobSub validation](Docs/EXTERNAL_VOBSUB.md).

## Audio conversion and synchronization

Keep Original remains the default; conversion requires an explicit choice.

- **TrueHD to FLAC:** HLS only, with manual audio timing at zero. The track must
  declare 24-bit precision, a matching mono, stereo, `5.1(side)` or `7.1` layout,
  and a native sample rate of 44.1, 48, 88.2, 96, 176.4 or 192 kHz. Unknown
  precision or speaker labels and other rates are rejected; 16-bit TrueHD is
  unverified. Conversion preserves the decoded channel samples, rate and layout,
  but does not retain Atmos objects. Direct HDR MP4 with subtitles is outside
  this route. Local conservation, cache and damaged-input checks passed; sampled
  Apple TV output covers stereo and 5.1(side) SDR, and stereo HDR-source playback.
  Those captures do not certify physical speaker routing or HDR rendering.
  See the [audio validation record](Docs/AUDIO_EXPANSION.md).
- **SDR HLS audio timing:** the repair retains the complete opening and audio
  tail. A positive adjustment delays audio; a negative adjustment holds the
  first video frame while the leading audio plays. The presentation includes
  that extra time. Local conservation, receiver-control and bounded digital-output
  checks passed, including Stop/replay and adjustment changes. Subtitle timing stays
  independent. See the [timing investigation](Docs/HLS_AUDIO_TIMING.md).

DTS-HD MA lossless preparation remains blocked: damaged extensions can decode
without an error while returning different samples. DTS-core output is not
accepted as a lossless substitute.

## Other limits

- Manual SDR audio adjustments are limited to five seconds in either direction. Lossless FLAC conversion requires zero manual adjustment.
- No video transcoder: unsupported codecs such as AV1, VP9 and MPEG-2 are not converted.
- No DCP packages, DVD/Blu-ray menus, disc navigation or encrypted media.
- Preparation can require substantial temporary disk space. Storage controls are in Settings.
- iPhone Remote control works, but title and artwork on the Apple TV-owned Lock Screen card are not reliable.
- OpenSubtitles has its own API key, account requirements and download limits.

See [recorded playback checks](TESTING.md) and [planned compatibility work](ROADMAP.md).

The [TS/MTS/M2TS validation record](Docs/TRANSPORT_STREAMS.md) covers copy-only preparation, four Apple TV output cases and the separate embedded PGS corrections. General Dolby Vision signaling from transport streams is not established by these tests.

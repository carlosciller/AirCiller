# Playback compatibility

This is the supported scope, not every format the bundled FFmpeg build can read. The Apple TV, television, audio equipment and local network also affect playback.

| Source | AirCiller behavior |
| --- | --- |
| MKV, MP4, M4V and MOV with H.264 or HEVC | Prepares a stream without encoding the video |
| Complete, unencrypted TS, MTS and M2TS with one program | Copies compatible H.264/HEVC and original audio; no disc menus, split-recording joining or live URLs |
| HDR and Dolby Vision | Preserves compatible video and metadata. Dolby Vision Profile 8.1 has been physically tested; other profiles are not universally guaranteed |
| AAC, AC-3, E-AC-3 and ALAC | Offered as original audio; the receiver must accept the channel layout and profile |
| FLAC soundtracks with a preserved channel layout | Original audio in HLS/fMP4 and direct HDR MP4; stereo and 5.1 have captured Apple TV evidence |
| Atmos carried by compatible E-AC-3 | Preserves the original stream; the playback chain determines Atmos output |
| DTS, TrueHD and other unsupported original audio | Requires an explicitly approved audio conversion; TrueHD Atmos metadata is not preserved by that conversion |
| SRT, WebVTT, ASS/SSA and embedded MP4 text | Selectable text with adjustable timing |
| Embedded Blu-ray PGS and DVD VobSub | Local Apple Vision OCR produces selectable text; preparation takes longer and recognition can be imperfect |

FLAC is supported as a movie soundtrack, not as a standalone music-file player. The current packager cannot retain some channel-mask overrides, such as a rear-channel `5.1` layout that becomes `5.1(side)` in fMP4. AirCiller explains the limitation and requires another track or explicit conversion approval. The [FLAC validation record](Docs/FLAC_AUDIO.md) lists tested cases and remaining limits.

## Subtitle appearance

HLS retains basic ASS/SSA formatting, alignment and positioning in WebVTT. Karaoke, animation, drawings and elaborate effects are simplified. The direct HDR MP4 route uses simpler styling. Apple TV controls the final presentation.

OCR preserves timing and approximate position, but does not reproduce the original bitmap or guarantee perfect text. Nothing is burned into the video.

Missing bitmap-subtitle language labels can be identified locally from the recognized text. Declared languages are preserved. Short or uncertain text stays undetermined and may not enable automatically on Apple TV.

Add external text files from the tracks panel, or place matching files beside the movie. External bitmap pairs such as `.idx`/`.sub` and standalone `.sup` files are not supported yet.

## Other limits

- No video transcoder: unsupported codecs such as AV1, VP9 and MPEG-2 are not converted.
- No DCP packages, DVD/Blu-ray menus, disc navigation or encrypted media.
- Preparation can require substantial temporary disk space. Storage controls are in Settings.
- iPhone Remote control works, but title and artwork on the Apple TV-owned Lock Screen card are not reliable.
- OpenSubtitles has its own API key, account requirements and download limits.

See [recorded playback checks](TESTING.md) and [planned compatibility work](ROADMAP.md).

The [TS/MTS/M2TS validation record](Docs/TRANSPORT_STREAMS.md) covers copy-only preparation, four Apple TV output cases and the separate embedded PGS corrections. General Dolby Vision signaling from transport streams is not established by these tests.

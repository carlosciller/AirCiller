# Architecture

AirCiller consists of a native application and one helper process for AirPlay 2.

## Main flow

1. `MediaProbeService` inspects the container, video, audio, subtitles, and chapters through `ffprobe`.
2. `StreamCoordinator` chooses one of two paths without modifying the original file.
3. `LocalHTTPServer` temporarily exposes the result on the local network using HTTP ranges and a random session path.
4. `AirPlayController` starts `airplay_helper.py`, which authenticates with the Apple TV and controls the AirPlay 2 queue through pyatv.
5. Receiver events update position, pause, resume, completion, and Now Playing metadata.

## Media paths

| Path | Use | Invariant |
| --- | --- | --- |
| Direct MP4 | HDR/Dolby Vision and selectable subtitles | Video is copied and never passes through an encoder |
| HLS/fMP4 VOD | General playback, separate audio, and WebVTT | Every playlist is finalized before playback starts |

The paths share discovery, control, and the HTTP server, but keep their packagers and physical validation separate. A single delivery must not change both paths.

## Boundaries

- Swift/AppKit/SwiftUI: interface, state, preparation, and local server.
- FFmpeg/ffprobe: analysis and remuxing. A pinned build is included in each AirCiller release.
- CPython and Python packages pinned from a lock file: AirPlay 2 bridge. The build fetches verified runtime archives and includes the tested result inside the app.
- Apple Vision: local, on-demand OCR for PGS subtitles. No remote service is involved.

## State and data

The playlist and history are stored in `UserDefaults`; AirPlay credentials are stored in the Keychain. Prepared media and OCR caches remain on the Mac. See [PRIVACY.md](PRIVACY.md).

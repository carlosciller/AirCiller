# Release notes

This page covers public AirCiller releases. Engineering notes and the physical playback matrix live in [TESTING.md](TESTING.md).

## 0.10.4 (31 August 2026)

### New

- Adds a subtitle preference for standard, SDH, or forced tracks in the selected language.
- Adds private local diagnostic exports and a focused action to reset authorization for the selected Apple TV.
- Adds AirCiller-managed FFmpeg and AirPlay runtime downloads with visible progress, cancellation, verification, and rollback. Homebrew remains available.

### Improvements

- Keeps Playlist and Recents rows aligned to a consistent two-line layout while retaining the complete filename in the hover text.

### Fixes

- Ignores embedded cover art when choosing the movie's video stream and maps the selected stream exactly during preparation.
- Stops both media analyses immediately when playback is stopped or another movie is selected.
- Ends the Mac playback session when Apple TV closes it, without leaving a running timer or showing a false connection error.

## 0.10.3 (26 August 2026)

### Maintenance

- Completes the first signed in-app update path.
- Improves the reliability of release validation.

Playback, audio, subtitles, and media preparation are unchanged in this release.

## 0.10.2 (25 August 2026)

### New

- Adds in-app update checks with a standard **Check for Updates…** command and a dedicated Updates pane.
- Adds native Playback, Components, and Storage settings.
- Adds preferred audio and subtitle languages, with a safe fallback to the file's default tracks.

### Improvements

- Keeps play, pause, skip, and the timeline better synchronized with macOS and the iPhone remote.
- Shows the installed FFmpeg and AirPlay engine versions, with clear maintenance actions.
- Updates the AirPlay environment to Python 3.13.15 and refreshes its locked dependencies.

### Updates and privacy

- Every app update is delivered over HTTPS, verified with a signature, and installed only after confirmation.
- Update checks wait until movie preparation or playback has stopped.
- Movies and subtitles remain local. AirCiller does not modify original files or transcode video.

## 0.10.1 (24 August 2026)

### New

- Adds selectable DVD VobSub subtitles through local Apple Vision OCR.
- Adds visible storage controls and a configurable limit for subtitle and prepared-media caches.

### Improvements

- Stops FFmpeg, analysis, subtitle extraction, and OCR promptly when playback is stopped or another movie is selected.
- Chooses the network route used by the selected Apple TV, improving reliability with VPNs and multiple adapters.
- Cleans abandoned preparation files automatically while preserving original media.

### Fixes

- Corrects a Vision OCR error that could turn music-note symbols into `&` and `s` around song lyrics.

## 0.9.8 (24 August 2026)

AirCiller's first public release.

### Highlights

- Streams Dolby Vision, HDR, H.264, and HEVC movies to Apple TV through AirPlay 2 without transcoding video.
- Supports selectable text subtitles, Blu-ray PGS through local OCR, multichannel audio, playlists, recent movies, and saved progress.
- Includes native English and Spanish localization.

### Reliability

- Confirms real media traffic before reporting that playback has started.
- Keeps healthy playback alive if the optional AirPlay feedback channel closes.
- Synchronizes pause, resume, seeking, and the timeline with the Apple TV remote.
- Keeps media, filenames, receiver details, and diagnostic addresses private.

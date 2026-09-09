# Release notes

Changes you can see or use. The [testing record](TESTING.md) keeps engineering and hardware-validation details.

## 0.12.6 (9 September 2026)

Keep your place when a movie moves or its drive is disconnected. Playlist and Recents now retain unavailable movies and their saved progress.

- If a movie cannot be opened, reconnect its drive and try again. Its entry stays in the library with an unavailable indicator.
- To find a moved file, right-click its entry in Playlist or Recents and choose **Locate File…**. Select the same movie at its new location; its Playlist position and saved progress are kept. Locating a file does not start playback.
- Trying to open an unavailable movie leaves the current playback alone. If the next Playlist movie is unavailable when playback ends, AirCiller stops with an explanation instead of removing it or skipping ahead.
- Choosing a file already listed in the library will not merge or overwrite either entry. Stop a movie before relocating it if it is currently preparing or streaming.

Entries removed by earlier versions cannot be recovered automatically. The existing 30-item Recents limit still applies.

[Library behavior and validation](https://github.com/carlosciller/AirCiller/blob/v0.12.6/Docs/LIBRARY_RECOVERY.md)

## 0.12.5 (9 September 2026)

Add subtitle files from Blu-ray and DVD alongside your movie. Previously, PGS and VobSub support covered tracks embedded in the movie; this release also accepts separate files.

### New

- Attach a Blu-ray PGS `.sup` file from the tracks panel.
- Attach a DVD VobSub `.idx`/`.sub` pair by choosing either file. Keep both files together with the same base name.
- Choose among the languages and populated tracks in a VobSub pair.
- Discover matching subtitle files beside the movie without adding the VobSub companion twice.

The selected image-based subtitle is read locally and turned into selectable text. Its first preparation can take time; recognition is cached for reuse. Original files are unchanged. Recognition may make mistakes and does not preserve the original bitmap's styling.

### Fixed

- Subtitles no longer stay hidden after the tested rapid forward/backward skip sequences from the Mac.

### Still limited

A brief subtitle gap can remain immediately after seeking over HLS. This release does not establish the same fix for rapid commands sent directly from the Apple TV or iPhone remote.

[PGS scope and checks](https://github.com/carlosciller/AirCiller/blob/v0.12.5/Docs/EXTERNAL_PGS.md) · [VobSub scope and checks](https://github.com/carlosciller/AirCiller/blob/v0.12.5/Docs/EXTERNAL_VOBSUB.md)

## 0.12.4 (6 September 2026)

Movies with supported FLAC soundtracks can now keep their original audio when sent to Apple TV. Leave audio output set to Original; no separate codec download is needed.

### New

- Play FLAC soundtracks whose channel count and speaker layout can be preserved during preparation.
- Use these soundtracks with or without selectable subtitles, including the existing HDR playback routes.

### Compatibility

Stereo and 5.1(side) were checked with captured Apple TV output. That verifies picture, digital audio and subtitle samples, not the routing of every physical speaker.

Some FLAC files carry a custom channel layout that the streaming container cannot retain. AirCiller explains the limitation and does not silently convert the audio or relabel its channels. Original video and audio remain unchanged in supported cases.

[Supported layouts and validation](https://github.com/carlosciller/AirCiller/blob/v0.12.4/Docs/FLAC_AUDIO.md)

## 0.12.3 (6 September 2026)

Open individual TS, MTS and M2TS video files from the file picker or Playlist. Compatible H.264 and HEVC video, including the tested HDR cases, is sent without re-encoding; original compatible audio remains the default.

### Fixed

- AAC audio could prevent some transport-stream files from playing.
- Blu-ray PGS subtitles could fail to load or appear too early in M2TS files.

### Compatibility

Use complete, unencrypted files containing one program. Files with several programs or an unreadable duration now produce a clearer explanation.

This does not add Blu-ray disc menus or playlists, joining split recordings, live TV streams, MPEG-2 video, or support for every audio codec found on a disc. Unsupported audio still requires explicit approval for conversion. General Dolby Vision support in transport-stream files is not established by the HDR tests.

[Format boundaries and validation](https://github.com/carlosciller/AirCiller/blob/v0.12.3/Docs/TRANSPORT_STREAMS.md)

## 0.12.2 (6 September 2026)

- Fixed missing or cropped Blu-ray subtitles when their resolution differs from the video.
- Fixed errors appearing after stopping or switching movies during analysis or subtitle recognition.

## 0.12.1 (5 September 2026)

### Fixed

- Rapid forward and backward skips keep the intended destination when replies arrive late.
- Fixed an unexpected quit at the end of a movie when the AirPlay connection had already closed.
- Stop cancels pending authorization and prevents delayed replies from starting a movie again.
- A Keychain access error is no longer treated as a missing Apple TV code.
- Cancel in the tracks panel leaves the active audio and subtitle choices unchanged.
- Invalid subtitle times and media-analysis timestamps no longer cause crashes or long stalls.
- OpenSubtitles responses are limited during download; duplicate and malformed results are handled safely.
- Restored legacy SSA subtitle alignment.

### Improved

- Simpler playback controls, system colors and materials, and a clearer empty window.
- Select an item in Recents without interrupting the current movie; use Return or double-click to play it.
- Faster ASS subtitle conversion.

## 0.12.0 (3 September 2026)

### New

- Find subtitles on OpenSubtitles.com from the tracks panel. Review file matches or search by title before downloading.
- See the subtitle language, format, release, SDH and forced-track details in the results.

### Improved

- Audio track and output format are separate choices. Original audio is the default; E-AC-3 5.1 and AAC stereo are clearly labeled as conversions.

### Fixed

- Long movies could become stuck loading after repeated seeking. The local server now releases abandoned requests correctly.
- A local file read failure now ends the session with an error instead of leaving the television loading.
- Stopping authorization or preparation no longer waits for helper output pipes to close.
- Seeking and buffering messages clear when playback resumes.
- Subtitle results without a filename extension are correctly identified as SRT.

OpenSubtitles is optional, uses credentials stored in Keychain and never receives the movie.

## 0.11.3 (2 September 2026)

- Playlist uses a single native selection for the mouse, keyboard and reordering.
- Selecting another row leaves the current movie playing.
- Press Return, double-click or use Play to start the selected movie.

## 0.11.2 (2 September 2026)

- Select Playlist items with the keyboard.
- Reorder the selected item with Option-Command-Up or Option-Command-Down, or use Move Up and Move Down in the menu.

## 0.11.1 (1 September 2026)

- Fixed repeated authorization prompts when a new pairing attempt began before the previous helper had closed.
- Improved recognition of Apple TV traffic on Macs using IPv4, IPv6 or a VPN.

## 0.11.0 (1 September 2026)

- FFmpeg and the AirPlay engine are now included in AirCiller. No separate component setup is needed.
- Engine versions have moved to Diagnostics.
- Playback engines update together with the app, after testing.

## 0.10.5 (31 August 2026)

- Improved cancellation during Apple TV authorization.
- Fixed overlapping changes to saved Apple TV credentials.
- Runtime checks now verify that the AirPlay engine can load.
- Reinstalling a damaged component can repair the current version; oversized downloads are stopped.
- Damaged Playlist and Recents data no longer causes the same failure on every launch.

## 0.10.4 (31 August 2026)

### New

- Choose standard, SDH or forced subtitles in your preferred language.
- Export a local diagnostic report or reset authorization for one Apple TV.
- Download and manage playback components from Settings, with progress, cancellation and rollback.

### Fixed

- Playlist and Recents rows keep a consistent height with long filenames.
- Embedded cover art is no longer mistaken for the movie's video track.
- Stop and changing movies cancel both media analyses.
- Closing playback on Apple TV no longer leaves a running timer or a false connection error on the Mac.

## 0.10.3 (26 August 2026)

- Improved update validation and verified installation through the signed in-app update feed.

Playback and track handling are unchanged.

## 0.10.2 (25 August 2026)

### New

- Check for signed app updates from the AirCiller menu or the new Updates settings.
- Set preferred audio and subtitle languages in Playback settings.
- Manage components and storage in Settings.

### Improved

- Better synchronization of play, pause, skip and the timeline with system media controls.
- Updated the AirPlay runtime to Python 3.13.15 and refreshed its dependencies.

Update checks wait until preparation and playback have stopped. Installation requires your confirmation.

## 0.10.1 (24 August 2026)

- Added selectable DVD VobSub subtitles using local text recognition.
- Added subtitle-cache limits and controls for clearing temporary media.
- Stop and changing movies cancel preparation and subtitle recognition more promptly.
- Improved network selection with VPNs and multiple adapters.
- Abandoned preparation files are cleaned up without changing original media.
- Fixed music-note symbols being recognized as letters around song lyrics.

## 0.9.8 (24 August 2026)

The first public release of AirCiller.

- Play compatible H.264, HEVC, HDR and Dolby Vision movies on Apple TV over AirPlay 2.
- Choose audio and subtitle tracks, including Blu-ray PGS subtitles recognized locally.
- Keep an ordered Playlist, recent movies and saved progress.
- Control pause, resume and seeking from the Apple TV remote.
- Use the app in English or Spanish.

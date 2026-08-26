# Testing strategy

AirCiller separates three levels of validation so that a successful build is never mistaken for successful playback.

## 1. Deterministic checks

`./Scripts/check.sh` validates formatting, compiles the code in strict Swift 6 mode, runs tests without private media, and checks the Python bridge through a simulation.

## 2. Local tests with media

Executables in `Tests/` that require a real file receive its path through an argument or environment variable. Media remains outside the repository. These tests validate containers, OCR, AVPlayer, and VOD playlists, but they do not prove that tvOS will accept the session.

## 3. Physical Apple TV matrix

A version is not considered ready to install until these cases have been completed separately:

| Path | Minimum case | Expected result |
| --- | --- | --- |
| Direct MP4 | HDR/Dolby Vision, E-AC-3/Atmos, with selectable subtitles | Correct picture and tracks; synchronized duration and position |
| HLS/fMP4 | Without subtitles | Complete VOD, no live indicator or preparation pauses |
| HLS/fMP4 | With WebVTT | Selectable, synchronized subtitles that are not burned into the picture |
| Control | Long pause and resume from the remote | AirPlay remains linked and the Mac does not sleep automatically |

After playback, also test stop, replay, and closing the app. Only then should the patch version be increased and the installed app replaced, while keeping a rollback copy.

## 4. Signed application updates

The first complete Sparkle update was validated on 26 August 2026. The installed app moved from AirCiller 0.10.2 (build 42) to 0.10.3 (build 43) through the public signed appcast, installed the update, and relaunched successfully. The resulting app bundle and every embedded Sparkle helper passed strict code-signature verification.

Version 0.10.3 did not change playback or media preparation, so this result validates the update path only. Apple TV playback remains subject to the separate physical matrix above.

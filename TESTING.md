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
| Control | Natural end of the current item | The Apple TV confirms completion and the next Playlist item starts once |
| Control | Rapid pause, resume and seek commands from Mac, Apple TV Remote and iPhone Remote | Commands remain ordered, the timeline stays synchronized and AirPlay remains linked |

After playback, also test stop, replay, and closing the app. Only then should the patch version be increased and the installed app replaced, while keeping a rollback copy.

## 4. Signed application updates

The first complete Sparkle update was validated on 26 August 2026. The installed app moved from AirCiller 0.10.2 (build 42) to 0.10.3 (build 43) through the public signed appcast, installed the update, and relaunched successfully. The resulting app bundle and every embedded Sparkle helper passed strict code-signature verification.

Version 0.10.3 did not change playback or media preparation, so this result validates the update path only. Apple TV playback remains subject to the separate physical matrix above.

## 5. AirCiller 0.10.4 physical validation

The 0.10.4 candidate completed the physical Apple TV matrix on 30 and 31 August 2026:

- Direct Dolby Vision/HDR MP4 with E-AC-3 audio and selectable subtitles.
- HLS/fMP4 VOD with WebVTT subtitles.
- Picture, sound, subtitle selection, remote commands, long pause, resume, and seeking.
- Remote exit returned AirCiller to a stopped state without a ghost timer or false connection error.

The original media files were not modified.

## 6. Post-0.11.0 reliability candidate

Build 46 completed the remaining physical control checks on 1 September 2026:

- The Apple TV reported the natural end of a movie and AirCiller advanced once to the next Playlist item.
- Rapid pause, resume, forward seek and backward seek commands from the physical Apple TV remote, iPhone Remote and AirCiller remained synchronized.
- Stopping from AirCiller ended playback cleanly without reconnecting, requesting a new authorization code or leaving a ghost session.
- AirPlay remained linked throughout the command sequence.

The validation used the candidate app directly. It did not replace the installed app or modify the original media files.

## 7. AirCiller 0.11.2 Playlist keyboard validation

The candidate and installed build 48 were checked locally on 1 and 2 September 2026:

- Up and Down select a Playlist row without starting playback.
- Option-Command-Up and Option-Command-Down move the focused row and preserve focus.
- Move Up and Move Down are also available in the Playlist and contextual menus.
- The original Playlist order was restored after testing.

This change does not alter either playback route.

## 8. AirCiller 0.11.3 Playlist interaction validation

Candidate builds 51 and 52 were checked locally on 2 September 2026:

- The Playlist uses one native AppKit selection with no competing custom highlight.
- A single click selects a row without loading it or changing the current movie.
- Up and Down move the selection without affecting playback.
- Option-Command-Up and Option-Command-Down keep the moved movie selected, and the original order was restored after testing.
- Return and double-click use the existing explicit Playlist playback action.

The playback pipeline is unchanged. Physical Apple TV playback was not repeated for this interface-only release.

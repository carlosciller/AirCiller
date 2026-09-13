# Future interface proposals

Status: exploration, 13 September 2026. The maintainer is refining the current AirCiller work separately; these proposals belong to a future version. This document does not schedule, select, implement or release a redesign. Keep changes on the design branch until the intended future integration. Recheck the current code and [dated audit](NATIVE_DESIGN_AUDIT.md) before implementing any finding.

Read the [reference dossier](NATIVE_DESIGN_REFERENCES.md) for source evidence and the [design guide](NATIVE_DESIGN.md) for invariants and acceptance. This document records the comparison and decisions still open, without repeating those rules.

## Shared comparison

Use identical content and commands when comparing compositions. All fixture data and interactions are fictional. The conversation preview is a web approximation; native materials, SF Symbols, menus, keyboard focus and accessibility must be evaluated in a subsequent native prototype.

Initial scenario: Costa al amanecer plays on Apple TV at 42:18 of 1:42:00 while La última estación is selected. Audio is Spanish, original 5.1, and subtitles are English. Selecting another row changes selection only. The current movie and destination remain explicit in every direction.

| Fixture | Video | Audio | Duration |
| --- | --- | --- | --- |
| Costa al amanecer.mkv | 4K HDR | Spanish/English 5.1 | 1:42:00 |
| La última estación.mp4 | 1080p | Spanish/English stereo | 1:36:00 |
| Bosque de invierno.mkv | 4K HDR | Spanish/English 5.1 | 1:50:00 |
| Un viaje lento.mov | 1080p | Spanish/English stereo | 1:28:00 |

All directions expose the same toolbar commands, destination, library selection, explicit activation, timeline and track editing. The inspector always names the movie whose session it changes. Its draft supports Cancel and a disabled unchanged Apply. The preview models the effect of applying tracks; it does not run preparation, play media, contact a receiver, search the filesystem or persist settings.

| Shared scenario | What the composition must make clear |
| --- | --- |
| Empty | A clear Open action; no fabricated session, time or track information. |
| Analyzing | The file is not ready; cancellation cannot make an incomplete analysis ready. |
| Ready | The available movie and destination, with an explicit playback action. |
| Preparing | The affected movie, phase and cancellation; no duplicate Play. The preview's 48% is a fixed synthetic fixture, not a measured estimate. |
| Awaiting receiver | The request has been made; playback confirmation is still pending. |
| Playing | Active movie, different selected movie, destination, position and matching Pause/Stop controls. |
| Paused | The same context and position, with Resume available. |
| Recoverable error | Identify the unavailable file or destination and expose recovery. Locating a file preserves that entry's identity and settings. |

The preview also shows the neutral analysis-pending state reached after cancelling analysis. Appearance, accent and active/inactive window controls are shared across all three directions. These explore presentation choices; their custom rendering does not reproduce the operating system's material engine.

## A. Mac essential

**Composition:** A sidebar library and a session detail area with balanced proportions. Tracks are optional in a right-hand inspector. Transport is integrated into the content instead of framed as an empty video canvas.

**References:** The Mac kit for familiar controls and grouping; Things for quiet surfaces and list rhythm; Landmarks for contextual panels.

**Hypothesis:** Someone can open a file, identify the target and begin playback with little explanation, while retaining access to the library.

**Risk to evaluate:** The interface may feel generic if its proportions, labels and transitions receive insufficient attention. Decorative cards are not a substitute for resolving that problem.

**Best fit:** General everyday use. This is the recommended starting candidate, not a selected or accepted design.

## B. Quiet cinema

**Composition:** A centered session title and transport, with the library arranged below. The optional inspector reduces the session's width without covering essential actions. The conversation preview keeps the library available; a hideable library is a possible later native experiment, not an implemented feature of this preview.

**References:** IINA's relationship between media and transport, with Apple's distinction between content and controls.

**Hypothesis:** Long viewing sessions benefit from a calm, easily readable control surface with the movie and Apple TV as the focus.

**Risk to evaluate:** Space and large type can obscure library context or suggest local video playback. No fake video frame, invented poster, online catalog or new media-preview feature is required for the comparison.

**Best fit:** Choose a movie, then mainly pause, seek or adjust tracks during a long session.

## C. Refined utility

**Composition:** A compact active-session strip above a file list with video and duration columns. Tracks are initially visible in the right-hand inspector. Selection and active-session identity stay separate even when the selected row receives stronger visual emphasis.

**References:** Things for orderly lists, Transmit for visible ongoing work and Pixelmator for contextual tools.

**Hypothesis:** Comparing several local files and adjusting language/track settings becomes easier when useful information is visible together.

**Risk to evaluate:** Density can turn a simple player controller into an unnecessarily technical tool. Reduce secondary columns at narrow sizes; preserve the filename, active session and essential commands.

**Best fit:** Frequent file switching and track adjustments. It should earn its additional visible detail through use.

## Decision and later native prototype

No direction has been chosen. Preserve the three compositions long enough to compare the same tasks and adverse states; avoid combining every attractive element into one more crowded window.

1. Identify current movie, selected movie, destination and phase without opening diagnostics.
2. Select another file without interrupting playback, then activate it explicitly.
3. Open tracks for the named session, change a value, cancel, and apply a real change.
4. Recover the missing file while retaining identity and settings; try another available library item.
5. Repeat at a compact width and in light/dark, another accent and inactive appearance.

Record which direction was preferred and the concrete reason. After selection, build a small isolated native SwiftUI prototype with synthetic state to evaluate actual materials, controls, keyboard/VoiceOver, resizing and movement. It should not contact the receiver or replace the daily app. Verify API availability and the existing macOS 14 path before choosing newer enhancements.

Before future integration, refresh the source baseline against the maintainer's completed work. Implement only the accepted scope in focused changes and use the existing [contribution gate](../CONTRIBUTING.md#minimum-validation), [native acceptance](NATIVE_DESIGN.md#acceptance-and-implementation-order) and playback checks for the behavior actually changed. The current study is documentation and simulated design exploration; no application build, receiver acceptance or release claim follows from it.

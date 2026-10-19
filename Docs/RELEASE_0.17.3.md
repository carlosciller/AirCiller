# AirCiller 0.17.3 candidate verification

Recorded on 19 October 2026. Target version 0.17.3, build 68. Publication and
installation require separate confirmation; this preparation record does not
establish either outcome.

## Scope

This candidate combines the [HTTP cleanup repair](HTTP_SERVER_CLEANUP.md),
[HLS subtitle seek repair](HLS_SUBTITLE_SEEK.md) and native editing/focus fixes.
Locked engines are unchanged. The zeroconf proposal in PR #30 is excluded.

The UI changes retain responder-chain Undo dispatch and derive menu titles and
availability from the active responder's UndoManager. Watched and unwatched
operations retain their own names through Undo and Redo.

## Native interface observations

The isolated AirCiller Test candidate was used with synthetic media, without
starting playback or modifying original movie files:

- Mark as Unwatched, Undo and Redo changed the library status and displayed the
  corresponding operation name in the Spanish Edit menu.
- An English-only candidate launch displayed English controls and the native
  Edit menu showed Undo Mark as Watched after the corresponding library action.
- Undo in the subtitle-search text field restored its original text without
  changing library status or the selected subtitle track.
- Applying a subtitle track left the inspector open and disabled Apply when
  no changes remained. With macOS Keyboard navigation enabled, accessibility
  inspection confirmed focus on Play after Apply and after closing the panel.
  The system setting was restored to its original disabled state immediately.
- At the declared minimum content size, the outer window measured 720 by 572
  points. The long filename, expanded inspector content and fixed Apply/Cancel
  footer remained accessible through the existing scroll views. No layout
  implementation change was needed for those cases.

The search sheet performs its existing initial search when opened; the query
used a synthetic fixture title. No subtitle was downloaded. These observations
do not establish every focus transition during playback or every text editor.

Focused strict Swift 6 tests passed for the independent Undo managers and real
library coordinator. A discarded menu-title observer was rejected after native
inspection showed SwiftUI overwriting its titles; it is not part of this code.
The complete final local gate passed with Swift 6 strict concurrency and
warnings-as-errors. The signed bundle measures 153,944,711 logical file bytes,
below the 165,000,000-byte budget. The isolated test preferences were restored;
the daily app's saved library and preferences were semantically unchanged.

## Playback evidence

No new receiver session is selected for the UI-only changes. The prior HTTP and
subtitle records retain their local and digital-output observations, including
their limitations. The HTTP server, subtitle writer and dependency locks are
unchanged from accepted main revision
`1765a82c245d5f7c9c388ebaea77b9b7d3a28ddb`. Coordinator edits concern watched-status
Undo only. Evidence reuse is not a new Apple TV run.

## Remaining release gates

Exact-head CI, signed package and public download checks,
and native Sparkle installation must pass before this candidate is reported as
released and installed. Public ad hoc signing is not notarization.

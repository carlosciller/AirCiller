# AirCiller 0.17.3 release verification

Recorded on 19 October 2026. Version 0.17.3, build 68, is
[published](https://github.com/carlosciller/AirCiller/releases/tag/v0.17.3) and
installed through the native Sparkle updater. The tagged preparation record
predates publication; this documentation follow-up records the completed gates.

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

## Distribution and installation

The reviewed candidate was `677c7d1bcc6461122b7a0fb7b8643fe63b9f8460`.
[PR #35](https://github.com/carlosciller/AirCiller/pull/35) merged as
`4582b2c5bbfb560b104a4e7c40d6ce7d7a49de91`, with identical tracked content.
The release tag points to that merge. All required CI runs completed successfully:

- [Candidate full check](https://github.com/carlosciller/AirCiller/actions/runs/39236238949).
- [Main](https://github.com/carlosciller/AirCiller/actions/runs/39237313614) and
  [tag](https://github.com/carlosciller/AirCiller/actions/runs/39237448711) explicitly
  reused that run after checking identical validation inputs.

The full archive SHA-256 is
`17e3cc866517dbe146f5c24fa670377088d4e951ec917e2580fe6d007bd8a145`.
The signed feed SHA-256 is
`55115361d1c461e640645d88c0622091aa0024a9a6b8bad32b6f0944f34c5e42`.
The app executable SHA-256 is
`c69732b5196a14936339b672b918ad85fe01feb7f0a7368a2f796fb6af11d824`.

Public HTTPS downloads of the full archive, all five advertised deltas, feed and
notes matched the local files. Sparkle verified the feed and all six archive
signatures. The latest-feed URL returned the same feed. The release body matched
the reviewed notes. The extracted app passed strict nested signature validation;
all 3,332 bundle entries matched the accepted local app by file bytes, modes and
symlink targets, without following framework symlinks.

The audit reports valid signature structure and bundled Python/FFmpeg. Missing
Developer ID, Hardened Runtime, notarization and Gatekeeper acceptance remain
the known public ad hoc distribution limitations, not passed checks.

A rollback copy of the daily-use 0.17.1 app was retained. Its native Check for
Updates displayed 0.17.3 and the reviewed notes, downloaded the update, and
offered Install and Relaunch. After installation, About showed 0.17.3 (68), and
the process ran from the existing daily-use path. All 3,332 installed bundle
entries matched the public package; strict code-signature verification passed.
Semantic preference comparison found only the updater's last-check timestamp
changed. Playlist, Recents, seasons, saved progress and other preferences were
preserved. AirCiller was left open and idle. No redundant receiver test was run.

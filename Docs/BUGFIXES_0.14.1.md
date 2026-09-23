# AirCiller 0.14.1 maintenance

Release preparation, 23 September 2026. Base: published 0.14.0,
commit `2780d4af8d7ac892686c0fcda595b08706c4ffe7`. The maintainer authorized a
maintenance release without Shortcuts. Publication and installed-app replacement
have not yet been recorded.

The patch covers library Undo/Redo, the live/persisted Recents limit, updater
menu availability, cache-error recovery and the contextual SDR audio-offset
warning. It does not change playback engines, supported formats or either
packager. The [Shortcuts implementation](SHORTCUTS.md) and its different signing
setup remain on their separate development branch.

The dated checks below belong to earlier candidates. They are retained as
evidence for their stated scope, not as a completed build, CI run or installation
of this isolated maintenance release.

## Update menu availability

During the recorded 0.13.0-to-0.14.0 installation, Check for Updates was disabled
in the application menu while the button in Settings worked. The same source
pattern remained in 0.14.0: a computed Swift Observation property read Sparkle's
KVO-backed value without subscribing to its changes. Opening another view could
read the new value while an existing menu retained its previous state.

`UpdateAvailability` observes Sparkle's publisher and transfers changes onto the
main queue into observable state. The controller's existing configuration,
startup and playback-busy gates are retained. Both UI entry points still use
the same controller property. This follows Sparkle's
[programmatic SwiftUI integration](https://sparkle-project.org/documentation/programmatic-setup/).
There is no polling, new dependency, preference write or change to the feed,
signing policy, scheduling, installation confirmation or playback paths.

The standalone regression uses an actual NSObject KVO publisher and Swift
Observation tracking. It covers initial availability, ready/busy/ready cycles,
observer invalidation, configuration and playback gates, and subscription-owner
cleanup. It passes with strict Swift 6 and warnings as errors. The reproduction
of the original user-facing failure is the recorded native installation, not a
claim that this fixture launched Sparkle's download UI.

The full contribution gate passed, including strict compilation, the regression,
existing local/simulated tests, publication checks and the bundled-app build.
The first run stopped on a prohibited phrase in the roadmap; its failed log is
retained separately. After correcting that sentence, the complete rerun passed.
The development bundle measured 155,702,060 logical bytes under the 165 MB limit.

On macOS 27, the freshly built normal application was opened from the build
directory while the daily app was closed. A scoped process check verified that
exact executable path. The menu was enabled; selecting Check for Updates showed
Sparkle's up-to-date result. After dismissing it, the menu was enabled again and
Settings showed the same enabled action. No update was installed, automatic
check preferences were not changed, and no library item was opened or played.
The test app was then closed. The daily 0.14.0 executable hash is unchanged.

This is native menu interaction plus a real feed check, not an installation test
or receiver test. Repeated availability cycles and playback-busy rejection are
covered locally. No Apple TV test is claimed or required by this observation-only
change; a later playback change has its own test scope. Publication and the
next installed-app update remain separate steps.

## Cache recovery and library Undo (22 September)

The temporary-cache regression first created a disposable read-only directory.
The previous cleanup returned successfully even though its file remained. Explicit
cleanup now reports the failure and still attempts other eligible directories.
The active session and its symbolic aliases remain excluded. Startup cleanup
keeps its existing best-effort behavior; it does not display a blocking dialog.

Settings reports subtitle, temporary-session and reusable-movie cache errors in
their own sections. Successful size reads clear old read errors without erasing a
failed cleanup. Clear remains available after a failed attempt even if an
approximate size read returns zero; playback/preparation still disables it.
Changing the subtitle-cache limit reports a failed trim after saving the limit.
The existing approximate subtitle/temporary size accounting is not replaced.

The new isolated storage regression exercises denied deletion, partial completion,
retry, missing enumeration roots, active-directory exclusion, subtitle-cache
failure and size/operation state recovery. The existing storage regression also
passes. Neither test clears the user's cache.

Library edits register named actions with the native window UndoManager. Undo
changes membership and order without rolling surviving entries back to stale
progress or metadata. No source movie is removed and Undo does not call playback.
Relinking a file invalidates this coordinator's earlier undo actions so obsolete
paths cannot be resurrected; unrelated text actions remain intact.

Restoration respects Recents' 30-entry capacity. Entries opened or updated since
a clear take priority, and older removed entries fill only the remaining space.
The first maintenance candidate left an existing discrepancy: `touchRecent`
could exceed the persisted limit. A later regression on the development branch
reproduced opening a 31st file. That isolated correction and its tests are being
carried into this patch: live insertion and decoded history use the same limit,
and evicting the focused oldest entry clears its focus. Reopening an existing
entry retains its order and progress. Acceptance of the port belongs to the
final maintenance gate below.

The local test covers native UndoManager execution, selection, redo, updated progress,
new entries, unavailable paths, malformed duplicate IDs and target-only action
invalidation. Real window-manager, menu and text-field interaction is a separate
acceptance check, not established by that model test.

`Scripts/check_library_coordinator.sh` additionally compiles the real coordinator
and services into a headless UUID-identified test bundle, with its own temporary
preferences domain. It checks removal, clearing, keyboard/drag reorder entry
points, selection, persistence and Undo/Redo without loading media or discovering
a receiver. Synthetic playback fields remain unchanged. The test rejects reuse
of an existing preferences domain and is part of the general gate. It still does
not establish that a live window supplies its UndoManager to the Edit menu.

The track editor now displays a contextual notice for a nonzero SDR audio offset
with an existing selected audio track. Tests exclude zero, absent tracks, unknown
probe state and HDR. This is information only: no timing, packaging or routing
code was changed and the repair remains pending.

The combined contribution gate passed, then passed again after the real
coordinator regression was added to the gate. Both runs include strict Swift 6,
warnings-as-errors, localization, local/simulated tests, content checks and the
development build. The final bundle contains 155,770,281 logical bytes within the
165 MB budget. The initial restricted attempt stopped at pip-tools' cache access
before tests and is retained separately; the complete runs used the existing
cache with normal filesystem access. No dependencies were regenerated or updated.
The daily executable's SHA-256 remains identical to the installed 0.14.0 record.

## Earlier verification boundary (22 September)

- Minimum window size and long inspector content, with English and Spanish.
- Focus and draft preservation after Cancel and Apply.
- Repeated commands and recovery, scoped to each reproduced failure.
- Native Edit menu Undo/Redo, removal/clearing/reordering and independent text editing.

The Mac was locked when native verification was attempted on 22 September. No
automatic unlock, Apple TV session or camera/microphone access was attempted.
The daily app and release version remain unchanged.

The manual SDR HLS audio timing repair remains separate. Do not mark it fixed
or widen either packager as part of this menu correction.

## Native maintenance checks (22 September, unlocked Mac)

These observations are preserved from the
[development-branch record](https://github.com/carlosciller/AirCiller/blob/f5a2780f863fbe20456df8ab34c0e3c7879a5d74/Docs/BUGFIXES_0.14.1.md#native-maintenance-checks-22-september-unlocked-mac).
The prepared CI candidate ran on macOS 27.0 (26A428), with a separate, initially
empty library and two synthetic movie fixtures. No movie was sent to Apple TV.

- Removing the first Playlist entry selected the survivor. Undo in the real
  Edit menu restored both entries, their order and the selection. Command-Shift-Z
  removed the entry again; Command-Z restored it.
- Moving the selected first entry down through its context menu retained its
  selection. Undo restored the previous order and selection.
- Clear Playlist removed both entries after confirmation; Undo restored both
  and their order. No source files were deleted.
- Opening a long-named fixture analyzed it without playback. Clearing Recents
  and undoing the clear restored the entry and duration without changing the
  loaded movie.
- Selecting an external subtitle enabled Apply, but Cancel retained the original
  disabled subtitle selection. Reopening showed no pending changes and disabled
  Apply.
- A nonzero draft SDR audio offset displayed the contextual notice. Cancel
  discarded the change. This tests the warning, not repaired audio timing.

The complete synthetic filename was visible at 960 by 650 points. The attempted
resize did not change the observed dimensions, so minimum-size layout was not
verified. English, independent text-field Undo, focus after applying tracks and
live-session preservation were not established by this check. The Edit menu
showed generic Undo/Redo labels; operation-specific wording remains unaccepted.
No appearance, language or security setting was changed. The daily executable
remained byte-identical during this check.

## Final maintenance release status

The release branch starts from the pre-Shortcuts maintenance changes and carries
only the isolated Recents correction from the later work. It keeps the existing
public ad hoc signing policy and does not include App Intent actions or the
experimental development credential service.

The final maintenance build, regression results, exact-commit CI, package and
installation checks are pending at the time of this entry. Record their actual
results here as they finish. The Shortcuts receiver captures do not certify this
different package, and no new Apple TV observation is claimed by the separation.

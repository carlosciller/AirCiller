# AirCiller 0.14.1 maintenance

Maintenance release record, 23 September 2026. Base: published 0.14.0,
commit `2780d4af8d7ac892686c0fcda595b08706c4ffe7`. The maintainer authorized a
maintenance release without Shortcuts. Distribution results are linked from
the final acceptance section; the daily-use app is kept intact during validation.

The patch covers library Undo/Redo, the live/persisted Recents limit, updater
menu availability, cache-error recovery, helper-output collection and the
contextual SDR audio-offset warning. It does not change engines, formats or either
packager. The [Shortcuts implementation](SHORTCUTS.md) and its different signing
setup remain on their separate development branch.

The earlier candidate checks below are retained for their stated scope. The
23 September maintenance build, native interface and package checks are recorded
separately at the end. CI, publication and installation are not implied by any
local result.

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
reproduced opening a 31st file. That isolated correction and its tests are now
included in this patch: live insertion and decoded history use the same limit,
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

## Maintenance validation (23 September)

The release branch starts from the pre-Shortcuts maintenance changes and carries
only the isolated Recents correction from the later work. It keeps the existing
public ad hoc signing policy and does not include App Intent actions or the
experimental development credential service.

### First local gate and public package

The complete public-policy `Scripts/check.sh` run passed, including strict
Swift 6, warnings-as-errors, local regressions, content checks and the ordinary
app build. Its log is retained privately as
`.build/release-0.14.1-maintenance-check.log`.

The resulting 0.14.1 (62) executable SHA-256 is
`fb39034659350f7d9b98cd228c837e710f2907850c3efebf6c64f799ca33924d`.
The bundle-size gate reports 155,737,939 bytes, including symlink storage once,
below the 165,000,000-byte limit.

The prepared full ZIP and delta from build 61 passed Sparkle's official signature
verification, as did the signed appcast. Applying the delta produces the same
complete bundle inventory as extracting the full ZIP. The verifier checks
version/build, release URLs, note contents, the public update key, required
signed-feed settings and strict ad hoc signatures. Original production artwork
and the complete pinned Sparkle, FFmpeg and AirPlay runtime trees match their
cached sources, including third-party signature files.

Both resulting bundles declare `ACShortcutsAvailable=false` and contain no
`Metadata.appintents`, local credential service or development markers. The
private receipt is retained in `.build/release-0.14.1/attempt-1/`. These are
local results for the first package, superseded by the helper fix below;
no anonymous download or installed update is claimed for this package.

### Native English interface

The separate Test candidate was launched in English using an `AppleLanguages`
process argument, without writing a language preference. Device discovery was
skipped and no Apple TV session was started.

- Removing one Playlist fixture selected a surviving entry. The real Edit menu's
  Undo restored the removed entry. Command-Shift-Z reapplied the removal.
- With the native Go to Folder sheet's text field active, Command-Z did not
  consume the library Undo action. The text itself did not undo, so successful
  text-editing Undo is not established. After dismissing the sheet and file panel,
  Command-Z restored all three Playlist entries.
- A long synthetic movie title remained readable in the English inspector at
  960 by 650 points. A draft audio offset of +0.05 seconds displayed the SDR
  limitation warning. Cancel discarded it; reopening showed no pending changes
  and disabled Apply.

This adds English native interaction and checks that a focused file-panel field
does not consume library Undo. It does not establish minimum-size layout,
operation-specific Undo menu wording, successful text-field Undo or focus after
applying tracks during a session. No new Apple TV output is claimed.

### Helper output collected at process exit

The [push run](https://github.com/carlosciller/AirCiller/actions/runs/35870835880)
failed the capture assertion at commit `4555721`; the
[PR run](https://github.com/carlosciller/AirCiller/actions/runs/35870979960)
passed for the same source. The original assertion did not report whether
status, stdout or stderr differed, so it does not identify the discrepant field.
Both attempts are retained. A local 512-process stress test also passed against
the unchanged implementation; it did not reproduce that CI failure.

Review found an unsynchronized interval between a readability callback consuming
bytes and appending them to its buffer. Finalization could take its snapshot
during that interval. A per-pipe collector now serializes reading, appending,
final draining and closing. Queued callbacks cannot read a closed or reused
descriptor. Nonblocking reads preserve cancellation when a descendant retains
a pipe, and read failures are propagated instead of appearing as successful
partial output. On normal exit it collects all available output from the owned
process, without waiting for future writes by independent descendants.

The regression now reports actual and expected results. It covers 512 rapid
exits with eight concurrent workers, exact stdout/stderr, streams larger than a
pipe buffer with a 257-byte retained tail, a zero-byte limit, EOF, queued callbacks,
an inherited open writer, nonzero exit, launch/read errors and cancellation under
two seconds while a descendant keeps the pipe open for four seconds.

The focused strict Swift 6 run passes. A separate integration probe using this
source passed five repetitions of the pinned FFmpeg/Python version commands and
actual pyatv imports. The real AirPlay helper returned a complete scan event and
found a receiver. It did not read credentials, authorize, pair or play media.
This establishes helper execution and discovery, not a new audiovisual test.

The affected call sites are short-lived discovery/authorization helpers and
component checks. The persistent playback helper, command transport, both
packagers, HTTP serving, media preparation and pinned engines are unchanged.
Existing playback evidence therefore retains its original scope; this patch
does not claim that Shortcuts captures certify the public bundle.

### Final acceptance

The corrected candidate passed the complete `Scripts/check.sh` gate with strict
Swift 6, warnings-as-errors and the public ad hoc signing configuration. The
log is retained as `.build/release-0.14.1-final-check.log`. The final executable
SHA-256 is `8188d07e38690865254dd824f39621614e53cb3355fe59ca8df63df7f2752064`;
the bundle-size gate reports 155,739,875 bytes under the 165 MB limit.

The English native observations above remain applicable: only helper output
collection and its tests changed afterwards, not the interface or library
behavior. No second identical UI or playback run is claimed.

Exact-commit CI, signed assets, anonymous downloads and the isolated Sparkle
update are tracked separately in
[release PR #19](https://github.com/carlosciller/AirCiller/pull/19).
The daily-use app is not replaced as part of these checks.

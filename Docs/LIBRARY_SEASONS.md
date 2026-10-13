# Library admission and season folders

Validation record for 0.15.0, 13 October 2026. Scoped candidate acceptance is
complete. The installed application was preserved during these checks.
Release and update steps follow [Distribution](../DISTRIBUTION.md).

## Behavior

Opening or dropping a supported movie stores it in Playlist before analysis.
Analysis or playback failure leaves the entry available for recovery. New inputs
preserve an existing analysis, preparation or playback session. Repeating a path
keeps one entry; filenames are retained.

Both file panels accept folders. A season has a native expandable outline, with
natural filename ordering so Episode 2 precedes Episode 10. Subfolders are scanned
recursively; extras become ordinary episodes in the same group. Hidden entries
and symbolic links are skipped. Import is on demand, reports progress
and partial failures, and can be cancelled. Completed folders remain after
cancellation. Further folder additions queue behind the current one. There is
no filesystem watcher or permanent background index.

Folder membership, expansion, watched status and position persist locally.
Existing Playlist entries decode without the new optional fields. Missing group
metadata can be reconstructed from episode folder identifiers. Relinking retains
episode state. Episode moves stay inside their season; moving a season moves
its episodes together. Removal changes only the library; Undo restores membership
and order. Original files are untouched.

The context menu supports watched/unwatched marking. Natural completion marks
an episode watched before the existing next-item flow. Manual marking preserves
the playback position, including when undone. Updates are deferred while a folder
import is active. Video packagers, original
audio, selectable subtitles, pinned engines and AirPlay transport are unchanged.

## Findings

- Single-file opening bypassed enqueueing; every compatible input is now admitted
  before analysis.
- New input called loadVideo and stopped the current session; active sessions are
  now preserved by the import boundary.
- The old table accepted only its own reorder drags. The outline accepts external
  file URLs and internal row moves.
- Repeated folder input initially cancelled an earlier pending import; imports
  now share a serialized queue.
- Reimport receipts count only newly admitted files, not existing duplicates.
- Marking an episode pending preserves its saved playback position; Undo restores
  watched status without discarding newer progress.
- A completed episode marked pending starts at the beginning. Partially watched
  episodes still resume at their saved position.
- A folder ending in a supported movie extension is imported as a season, not
  also admitted as a standalone movie.
- The first outline showed overlapping secondary text. Explicit row sizing is
  implemented; revised native rows and collapse focus were checked successfully.
- A queued folder disappearing before its scan is now reported as an import
  failure instead of being silently skipped. A production-coordinator regression
  reproduced the omission before the fix and passes after it.
- Internal drops on episode rows resolve to insertion before or after the row.
  Root boundaries next to the current season accept its first or last position;
  moving an episode into another season remains disallowed. Local AppKit
  delegate tests cover these destinations, whole-season moves and Undo.
- First/last episode movement availability now matches the season boundaries
  in both context menus and the main menu. Regression coverage verifies disabled
  commands after native menu validation.
- Admission now uses a set of paths and updates the observable list once, replacing
  repeated linear membership checks. No timing gain is claimed without a benchmark.
- The superseded flat table and its renderer had no remaining callers after the
  outline integration and were removed.

## Acceptance matrix

| Requirement | Current evidence | Remaining |
| --- | --- | --- |
| Single-file admission | Real coordinator regression; native Open retained an invalid-media entry after failed analysis; Finder Open With analyzed an existing episode without a duplicate; failed-media entry retained after restart | None in recorded scope |
| Multiple inputs and duplicates | Coordinator duplicates, mixed-rejection, special-name and external-path regressions; separate APFS volume; actual Finder folder drop and duplicate reimport | Physical removable-drive behavior is not inferred |
| Active-session preservation | Local coordinator state and captured season reimport during playback passed; native Finder opening analyzed without starting playback | Adding during playback uses recorded receiver evidence |
| Folder order and recursion | Scanner order, recursion, hidden files, link cycles and partial-access fixtures; native reimport returned zero new files and retained order | None in recorded scope |
| Groups and expansion persist | Add panel, external folder drop and final restart retained both groups and collapsed/expanded states | None in recorded scope |
| Manual watched and Undo | Native menu/Undo; pending/progress regressions; final native marking persisted across restart | None in recorded scope |
| Episode keyboard move and Undo | Native keyboard/Undo; maintainer confirmed upward/final pointer drops with insertion line; delegate regressions; final restart retained manual order | Automated pointer gesture remains unreliable |
| Remove season and Undo | Native removal/Undo and production coordinator regressions; source hashes unchanged after checks | None in recorded scope |
| Completion and next episode | Injected receiver-end regression and captured natural-end season transition; watched/progress saved and one next load | Captured output is sampled, not a whole commercial film |
| Cancellation | Scanner pre-cancel/in-flight and coordinator queued-cancel/retry regressions; clean candidate displayed live progress and native Cancel stopped a large import with no additions | None in recorded scope |
| Legacy data | Decode, persistence, corrupt group recovery and episode relink-state regressions; final candidate restart passed | None in recorded scope |
| Appearance and focus | Two-line rows, collapse focus, manual drag, long selection details, minimum 960 x 650-point window and native zoom observed | Older macOS and a full accessibility settings matrix not exercised |
| Playback routes and controls | Nine-case captured batch including both six-minute pauses; fresh season recheck; later library-only native interactions passed | No new receiver run for playback-independent changes |
| Contribution gate | Final complete Scripts/check.sh passed after removal of temporary source diagnostics, including strict build and package verification; final public-content and diff checks passed | None in recorded scope |

The nine-case batch uses playback-check executable SHA-256
`aa758f8cd84db46bc323f9b39f54d96389fa149e463374b710097484a3417375`.
The subsequent candidate changes address admission of movie-suffixed folders and
restart of completed episodes marked pending. Local regressions cover both;
a freshly rebuilt runner rechecked season admission, live reimport and natural
transition using a folder ending in `.mkv`. The other recorded cases use inputs
whose initial-position and folder-admission decisions are unchanged by these fixes.
The targeted runner SHA-256 is
`61ff34268f171dfaae861260a3c559025b68b82b96c0c1d638f05974f037b1d3`.

Local checks do not establish television output. Native observations refer to
the candidate revisions named below; the final clean build removes diagnostics
without changing the tested interaction logic.
Private fixtures, snapshots and logs remain under `.build`, outside public Git.

### Native drag verification

The latest native automation did not establish a successful pointer reorder.
Temporary diagnostic callbacks showed the writer selecting the endpoint row,
not the intended starting row, valid destination resolution, and an
accept callback only after a subsequent click. Two contrasting gestures showed
this mismatch. This is evidence of an unreliable automated gesture, not proof
that the application rejects it. The maintainer subsequently confirmed both
upward and final-position manual drops and the insertion line. The native tree
also showed Episode 2 after Episode 10 following that check. Diagnostic logging has been removed
from the source. The candidate used for this check had identical drag logic
and temporary numeric-only diagnostics; no private filenames were logged.

These later changes affect library import failure reporting and native outline
interaction only. Neither packager, AirPlay transport nor the recorded playback
scenario inputs changed. The television was released after the captured checks;
no additional receiver session is reserved for this work.

### Final native admission and persistence checks

Finder delivered a new Season 2 folder through the outline: the maintainer
confirmed addition, and the live native tree showed one group, one episode and
the one-file import receipt. Repeating Season 1 produced a zero-new-files receipt
without duplicating its three episodes. The first ambiguous confirmation was
resolved by this new-folder check; it was not used as evidence of a defect.

Native Open admitted a deliberately invalid MKV before reporting the real local
analysis error. Finder Open With selected the isolated candidate, analyzed a
valid episode and did not change the default file association. After manual
reordering and watched marking, a full app quit/relaunch retained Season 1's
collapsed state, one watched episode, the order 1/10/2, Season 2 and the invalid
entry. Expanded and collapsed focus, the minimum window and native zoom were
observed. The test app was closed and its original isolated preferences restored.
The installed executable and all three original synthetic episode hashes remain
unchanged. No publication or installation was performed.

### Final cancellation check

The clean candidate was rebuilt from the checked source without diagnostic
logging. A private fixture with 100,000 empty media-named files made the normal
on-demand scan long enough to exercise its real interface; no delay or test-only
scanner was injected. The native tree showed 69,952 inspected entries, a progress
indicator and Cancel. Clicking Cancel changed the receipt to Import cancelled,
removed progress controls and retained the original three-item Playlist without
adding a season. No probe or playback started. Later native readback showed no
late additions. The test-only files were moved to Trash after the app closed,
and the candidate preferences were restored again.

## Completion audit

### Release preparation for 0.15.0

Build 63 adds singular/plural library counters and an explicit no-new-files
receipt for duplicate folder imports. These changes affect presentation only;
admission, ordering, watched/progress fields, cancellation, playback selection,
both packagers, AirPlay and pinned runtimes are unchanged from the accepted
candidate. Localization regressions cover both languages. The scoped receiver
evidence above is carried forward on that comparison, not reported as a new run.

The public notes, README, privacy description and roadmap have been reconciled
with this delivery. Publication and installation are tracked separately.

The scoped library behaviors are covered by the matrix above, production-code
regressions and recorded native interactions. The captured nine-case playback
batch and targeted season transition check cover the shared playback boundaries;
later outline/import-reporting changes leave both packagers, engines and these
scenario decisions unchanged. Removed code has no remaining callers. Final
checks use Swift 6 strict concurrency and warnings-as-errors.

This is candidate acceptance, not a published release or daily installation.
Coverage is bounded: digital output is sampled, a disk image does not prove
physical removable-drive behavior, and this run is not an exhaustive older-OS or
accessibility settings audit. The pre-existing SDR manual-audio-offset defect
remains outside this library delivery, as recorded in the roadmap.

### Separate filesystem

The coordinator season suite was also run on a mounted, disposable APFS disk
image. It checks that the filesystem differs from the normal temporary directory,
then creates its own UUID-named fixture folder. Import, ordering, persistence,
manual state, Undo, cancellation and retry passed. The image was detached after
the run. This is a filesystem test, not a physical removable-drive observation.

For an explicitly prepared disposable volume, the opt-in command is:

```sh
AIRCILLER_TEST_VOLUME_ROOT="/absolute/path/to/test-volume" ./Scripts/check_library_coordinator.sh
```

The ordinary contribution gate uses the normal temporary directory and requires
no disk image or additional installed dependency.

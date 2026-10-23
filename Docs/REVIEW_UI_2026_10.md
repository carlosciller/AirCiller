# Interface and library review, October 2026

Source review and focused local checks on 23 October 2026. The working tree was
based on `68410591e3786705f54938326e152be94fa564d1` and already contained private
remote-control and playlist-continuity work. This record covers the UI changes
described below; the final combined gate and native candidate acceptance belong
to the overall review. No installed app was replaced by this work.

## Scope and design decisions

Reviewed the main window, library sidebar, native season outline, track inspector,
device picker, pairing sheet, all standard Settings tabs, OpenSubtitles settings
and search views, and the About panel. Supporting review covered track names and
selection preferences, command availability, session presentation, library
admission and persistence, Undo, folder enumeration, and system Now Playing
publication and command callbacks. Private-control transport and its Settings
view are covered by the separate remote-control review.

The review retains the accepted [native design](NATIVE_DESIGN.md): system window
chrome, semantic colors, independent library selection and playback, native menus,
the expandable outline, and an initially visible Audio and Subtitles inspector.
No new glass layers, color scheme or replacement list control were introduced.
VoiceOver-specific work remains outside this delivery at the maintainer's request;
ordinary keyboard behavior and existing accessibility labels are retained.

Apple's [menu guidance](https://developer.apple.com/design/human-interface-guidelines/menus)
ties commands and availability to the current selection and context. Its
[Undo guidance](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo)
calls for predictable results and descriptive command names. These principles
support the selection and Undo changes here; they do not establish runtime visual
acceptance on every supported macOS version.

## Defects corrected

### Season selection and movement

Selecting a season previously cleared the coordinator's library focus. The
outline's context menu and local keyboard handler could still move the season,
but the menu-bar commands saw no selected item and were disabled. A private
selection retained by the outline could also restore an explicitly deselected
row on refresh.

The coordinator now owns both episode and season selection. Context menus,
menu-bar commands and outline keyboard actions use the same movement rules.
Deselection clears shared focus. Undo restores season selection as well as
membership and order, without changing the active playback item.

The integrated regression suite then exposed a collapse-ordering defect:
AppKit deselects a selected descendant before its `DidCollapse` notification.
Clearing shared focus at that point erased the information needed to select the
parent. The outline now selects the still-visible season in `WillCollapse`,
before AppKit removes the descendant. The strict regression assertion failed
before this correction and passed afterwards.

Affected code: `NativeSeasonOutline.swift`, the library-selection and Undo
sections of `StreamCoordinator.swift`.

### Adding a movie during a pending playback decision

The input boundary protected analysis, preparation and streaming, but omitted
authorization, audio-consent and automatic-start waits. Opening another movie in
one of those phases could call `loadVideo`, replacing the pending session and its
decision. Even a rejected input could replace the visible session explanation.

Admission now uses the existing command-availability boundary for all cancellable
session phases. A valid input is retained in Playlist while the pending session
continues; invalid input is reported through the import receipt. Explicit Play
and Stop retain their existing behavior.

Affected code: `StreamCoordinator.handleURLs` and `enqueue`.

### Subtitle preference precedence

The SDH setting promised to prefer SDH when available, but the selector ranked
every text track before every bitmap track. A normal English SRT therefore beat
an available English PGS SDH track. Similarly, a forced text track could beat a
normal bitmap track when normal subtitles were requested.

The requested subtitle kind now ranks first. Text remains preferred over local
OCR when both tracks satisfy the same kind. Forced-only still leaves subtitles
off when no matching forced track exists. No OCR or subtitle-packaging code was
changed. Selecting the requested bitmap track may take longer on its first use;
the inspector already describes this local preparation step.

Affected code: `SubtitleTrackSelection` in `MediaModels.swift`.

### Track draft recovery and output labels

An edited inspector draft was correctly prevented from overwriting settings
changed elsewhere, but Apply became disabled without an explanation. The panel
now identifies the conflict and offers **Load Current Tracks**. That explicit
action discards the stale draft; merely receiving a remote update does not.

The main session summary no longer carries the source track's Atmos label or
channel count into a chosen conversion. The existing audio-plan line describes
the selected converted output. Original mode retains the source summary.

Playback Settings now explains that consent can cover equivalent following
episodes in the same session and ends on Stop or another explicit playback
choice. Both English and Spanish were updated.

Affected code: `TrackSettings.swift`, `TrackSettingsView`, `MainWindowView.swift`,
`AudioTrack.sessionSummary`, `PlaybackSettingsView`, and both localization tables.

## Local evidence

| Check | Evidence in this review |
| --- | --- |
| Subtitle preference regression | The new mixed text/bitmap preference case failed against `MediaModels.swift` from the base commit with `PreferenceBeforeOCRCost`, code 14. The candidate passed the same case. |
| Track metadata and output summaries | Strict Swift 6 compilation and execution passed. Coverage includes original Atmos/5.1 labels, omission of those source claims for every conversion mode, SDH and normal kind priority, text preference within a kind, and forced-only exclusion. |
| Track draft rules | Strict compilation and execution passed for changed, unchanged, busy, stale and reloaded drafts. A stale dirty draft conflicts; an untouched draft can follow external state; reloading leaves no change to apply. |
| Localization | The existing smoke test passed against both updated tables, including equal keys and existing formatting/Info.plist checks. |
| Production library coordinator | The final focused coordinator run passed (exit 0) with pending audio-consent admission, preserved decision/session identity, rejected-input presentation, shared season command availability, whole-season movement, Undo, collapse and deselection checks. It also ran the direct-startup check supplied by the playback review. |
| Collapse boundary | The integrated run failed with `collapsing a selected episode returns selection to its season` (exit 133). Moving parent selection to `WillCollapse` fixed the notification-ordering cause. The same assertion passed in the final focused run, without weakening its selection or identity checks. |
| Formatting | Strict formatting lint passed for the changed views, models and tests. `git diff --check` passed at this checkpoint. |

The coordinator test uses its existing fresh preferences domain, synthetic inputs
and hidden AppKit objects. It does not connect to Apple TV. No television output
or physical pointer interaction is inferred from these results. Two earlier
compilation attempts were invalidated by concurrent source edits. The subsequent
collapse assertion failure was a real behavioral failure, separately reproduced
and corrected; the final complete focused run passed after that correction.

## Coverage inventory and limits

- `LibraryCoordinatorSmokeTest` exercises real coordinator admission,
  persistence, selection, season grouping and native outline delegate behavior.
  `HistoryStoreSmokeTest`, `LibraryListUndoSmokeTest`, `SeasonFolderSmokeTest` and
  `NativeUndoCommandsSmokeTest` cover their respective supporting policies.
- `TrackMetadataSmokeTest` and `TrackSettingsSmokeTest` cover naming, preference
  and draft decisions. They do not render the inspector or prove focus return.
- `PlaybackCommandAvailabilitySmokeTest` and `SessionPresentationSmokeTest`
  cover shared command and visible-phase policy. This review did not change
  either policy type.
- `OpenSubtitlesServiceSmokeTest` covers local hashing, REST request construction
  and response decoding. Live account behavior and the search sheet's rendering
  are not established by those tests. Network and credential-boundary changes
  are owned by the separate distribution review.
- The localization suite checks resource consistency, not every rendered string
  or every long filename. The native checks below remain necessary.
- `SystemNowPlayingController` was source-reviewed, including command cleanup,
  disabled idle commands, finite timeline guards and throttled metadata updates.
  No fresh iPhone lock-screen title/artwork or system media-key acceptance is
  claimed. Those features were not expanded in this UI delivery.

## Native checks for the combined candidate

The isolated UI candidate was exercised on 23 October, with executable SHA-256
`4bb2535a80fd9a2c4adae5e65f7f9b984bbd3bcea635545bbf3542b774530445`.
It used the auxiliary preferences domain and disposable two-season fixtures;
the installed app and its library were not opened or changed.

- A selected season enabled the correct Playlist menu boundary, moved as a
  whole using the menu and Command-Option-Down, and returned to its prior order
  and selection with Undo. Collapsing a selected child selected its parent.
- Arrow navigation selected a different episode without loading or playing it.
  Opening Episode 1 left the separate Episode 2 library selection intact. Its
  deliberately long name was available in the selection detail without changing
  the outline row height.
- With original E-AC-3 5.1 loaded, editing the output to stereo AAC enabled Apply
  and explained when the change would take effect. Applying while idle changed
  the selected plan without encoding or contacting the TV, removed the source
  5.1 claim from the header, retained the open inspector and disabled unchanged
  Apply. Atmos-specific labeling is covered by the model regression, not this
  fixture.
- The main window, inspector and changed Playback Settings text were inspected
  in English/dark and Spanish/dark. Spanish/light was then observed in the main
  window and Settings after explicit permission; the system's original dark
  appearance was restored and its selected state verified.
- The 960 by 650 and reduced 840 by 585 point windows kept the inspector footer
  and actions visible. The long selected title wrapped in the session detail.
  This does not establish the exact declared 720 by 520 content-size boundary;
  the automation did not produce that final resize.

The live stale-draft reload presentation and importing during a visible
authorization/consent prompt were not separately triggered in this UI pass.
Their actual coordinator/policy regressions passed, as recorded above. A full
VoiceOver campaign, every system keyboard-navigation setting and every supported
macOS version are outside this observation. These limits must not be relabeled
as native passes. The following list retains the directed checks for any later
candidate that changes these interactions:

These checks concern the affected interactions and do not require a new HDR,
audio-codec or subtitle-rendering battery on Apple TV:

1. Select a season between other library roots. Compare Move Up/Down in the menu
   bar and context menu, move it with the keyboard, then Undo. Episodes must stay
   together and the season must remain selected. Check first/last boundaries.
2. Select an episode, collapse its season, and check parent selection. Deselect a
   row, then cause an ordinary library refresh; the old highlight must not return.
3. In a controlled pending playback decision, add a movie through the open/drop
   boundary. The new entry must appear without replacing the pending movie or
   its approval. Rejected input must leave the pending explanation intact.
4. Edit a track draft, then change the current track settings through a separate
   controlled entry point. Check the conflict explanation, explicit reload,
   disabled unchanged Apply, Cancel, and return of focus after a real Apply.
5. Inspect an Atmos or multichannel source with a selected conversion. Its main
   summary must not imply source Atmos/channels are the output; the audio-plan
   line must describe the chosen conversion.
6. Check the changed inspector/footer in English and Spanish, at the declared
   minimum window size and normal size, with long filenames/track labels. Verify
   light/dark appearance and access to Apply, Cancel and the reload action.

## Performance finding

This UI review produced no quantified performance improvement. The outline
rebuilds its nodes and reloads when stored queue progress changes, and groups are
assembled with repeated scans of the queue. These are source observations, not
evidence of a noticeable delay in the maintainer's library. Measure a realistic
large-library interaction before changing that architecture; no list rewrite or
timing claim is included here.

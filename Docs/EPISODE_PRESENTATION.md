# Episode display names

Delivery 4 of the local-library goal. Presentation only: file paths remain library
identity, manual order remains authoritative, and the original filename stays in
the row tooltip and selected-file detail.

Actual queue examples justify one narrow convention. A season entry whose stored
title still equals its original basename can display a single `S01E01` token and
episode title, omitting a recognized resolution/release suffix. For example,
`Example.Show.S01E01.Let.You.Down.1080p.BluRay.Remux` displays
`S01E01 · Let You Down`. Dots/underscores in the episode title become spaces.
This does not derive ordering, watched status, show metadata or playback position.

Unrecognized releases, compound episode numbers, movies outside a season and
already-customized stored titles retain their existing presentation. There is no
online lookup, file rename, broad punctuation cleanup or irreversible migration.
The original `title` and `path` are not overwritten by automatic presentation.

The episode context menu offers Edit Display Name, using an attached native sheet.
Save stores an optional `displayTitleOverride`; Reset removes it, restoring the
automatic/original fallback. Cancel changes nothing. Names must be nonempty,
single-line and at most 160 characters. Correction is reversible through Undo;
Redo, persistence and explicit file relocation preserve the appropriate override.
Edits change only this field, not progress, watched state, membership or order.
Legacy JSON without it still decodes. No daily library is migrated during tests.

The actual coordinator tests cover the concrete pattern, ambiguous fallback,
legacy decode, correction bounds, persistence, original identity/progress, reset,
Undo/Redo and relinking. An initial test compilation incorrectly placed a throwing
decode inside `precondition`; the decode is now performed before the assertion.
The first full gate then found a test fixture registering its reset outside an
explicit Undo group. Correct grouping fixes the fixture; assertions and production
Undo behavior remain intact. The corrected coordinator suite passed in the
retained gate remainder; neither earlier failure is called an application pass.

The initial native candidate showed the cleaned row and Continue Season title,
with the full original in selected-file detail. The standalone modal editor was
not reliably operable by automation; the final candidate uses an attached sheet.
The final sheet candidate compiles with strict Swift 6 and warnings as errors.
The split gate ends successfully in `.build/local-library-publication-build-final.log`.
Its ordinary executable is SHA-256
`05c123d038627a42e81f275c37c24b1972abf5e899f67e8f2d2771ddef50bfc1`.
The later sheet edit affects only presentation of this editor; coordinator/model
regression inputs remain unchanged. At that checkpoint native
save/cancel/reset/restart acceptance was pending: the automation repeatedly lost
its valid app/element target between context-menu observation and interaction.
Those attempts are not recorded as successful edits, user interventions or
application crashes. The completed native check follows below.

Recents and receiver/lock-screen titles are outside this presentation change.
They retain original names; this does not deploy or change the private connector.
No Apple TV test is needed for a stored Playlist display override.

The installed executable remains unchanged. Comparing daily preferences with the
goal checkpoint found identical library and preference values except Sparkle's
`SULastCheckTime`. That timestamp was not restored or attributed to a proven
cause. No daily-library override or migration occurred.

## Completed native editor check, 2 November 2026

A UUID-isolated check compiled the current production view and coordinator with
three temporary, fixed diagnostic messages inside `AIRCILLER_UI_CHECKS` blocks.
The messages contain no paths or entered names. They established that the failed
menu-item automation did not reach the action; it was not evidence of an alert
opening and closing or a crashed process. Native menu keyboard search (`E`, then
Return) activated Edit Display Name. Rebinding the app target after the sheet
opened allowed field and button interaction. One positional menu attempt instead
opened Locate File; it was cancelled without selecting or relinking anything.

Observed in the actual production interface:

- English/dark: Save changed the row to `My Episode`; Undo restored the automatic
  name and Redo restored the correction. All kept 00:42 progress and the same
  original filename. Editing a different value and pressing Cancel retained
  `My Episode`.
- After Quit and relaunch in Spanish/light, both the row and Continue Season
  summary retained the corrected name and 00:42 progress.
- Saving a blank name kept the edit sheet open with the localized length/single-line
  guidance. Reset from that sheet restored `S01E01 · Let You Down` without changing
  the saved position or original filename in the selection detail.
- A second Quit/relaunch retained the reset automatic name and 00:42 position in
  both the row and Continue Season summary. The auxiliary app then closed.

Private evidence: `.build/episode-editor-diagnostic-runtime.log` records Save and
Cancel responses; `.build/episode-editor-diagnostic-runtime-es.log` records invalid
Save, the replacement validation sheet and Reset. The synthetic final window is
saved as `.build/episode-editor-final-es-light.jpg`. The check executable SHA-256
is `5880937e70f84aa7c7b554fcc4d5ee266be0502f47dfee7aa5859c806417cdd0`.

The diagnostic blocks were removed after observation. `NativeSeasonOutline.swift`
then matched the accepted `ba358ea` source byte for byte; no shipping runtime
behavior changed after its final strict build. The only tested-build difference
was excluded, fixed-text check instrumentation, not alternative editor logic.
Do not rebuild or repeat television checks for removal of those messages.
Pointer activation remains an automation limitation; successful native keyboard
activation, editing and persistence are the acceptance evidence. No spoken
VoiceOver or older-macOS campaign is claimed.

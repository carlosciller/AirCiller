# Native design baseline audit

Date: 13 September 2026. Scope: design research and future implementation planning only. No application sources, preferences, playback, versions or installed binaries were changed for this audit.

## Evidence and boundaries

- Observed the installed AirCiller 0.12.6 (build 59) main window in its no-movie-selected state with an existing Playlist, plus the Playback and Updates settings pages. Used an app screenshot and accessibility tree. Returned to the main window and restored the previously selected settings page. No movie was opened or played, and no preference value was edited.
- Read UI and coordinator source on the development checkout at `9f6d69a`; that checkout also contains pending HLS work outside this audit. Rechecked the findings below against public main `b541e73`. The main app UI, native table, online-subtitle view and error definitions match between these revisions; Settings and coordinator code have branch differences, so links identify symbols, not portable line numbers.
- The source findings are code-confirmed opportunities/risks. Their runtime effects were not exercised in this audit. VoiceOver speech, keyboard-only operation, resizing, contrast, alternate appearances, loaded-movie/tracks screens and receiver output remain untested.
- No private screenshots, library entries, media filenames or receiver identifiers are included. Read [the design guide](NATIVE_DESIGN.md) for official sources and acceptance criteria.

## Retain

The application already has native window controls, a collapsible split view, AppKit Playlist selection and drag handling, standard menus, system open/save panels and grouped settings. Preserve explicit activation separate from selection, track editing with a draft, and diagnostics shown only when requested. The existing [interface decisions](STABILITY_REVIEW.md#interface-and-documentation) discourage stacked custom glass and a yellow background wash; this proposal retains those decisions.

The observed main window has a clear empty-state action and a visible destination picker. Its sidebar repeats product branding and presents long raw filenames in compact multi-line rows. That is a hierarchy/legibility opportunity; the screenshot alone does not establish a contrast or accessibility failure. The observed Updates page exposes engine/update implementation terms that could move into optional details.

## Prioritized findings

Priorities order future work. They are not newly reproduced playback failures or completed fixes.

| Priority | Finding and code evidence | Proposed change and direct check |
| --- | --- | --- |
| P1 | Menu playback commands have no equivalent availability rule to the disabled Play control. `AirCillerApp.commands` calls `togglePlayback`; without an active stream that calls `start`, including during preparation. [App UI](../Sources/AirCillerApp.swift), [coordinator](../Sources/StreamCoordinator.swift). | Share command availability across menus/buttons/shortcuts. Reproduce a preparation attempt followed by Space and ensure no duplicate attempt is started. Test text-field/list contexts and retain Stop cancellation. Treat as playback-control work. |
| P1 | `clearQueue` and `clearRecent` immediately save empty arrays. The corresponding library buttons invoke them directly; no Undo integration is present. Recent entries include saved progress. [Coordinator](../Sources/StreamCoordinator.swift), [library UI](../Sources/AirCillerApp.swift). | Prefer native Undo restoring exact entries, order and progress. Otherwise confirm bulk removal with its consequence. Test with disposable library data, never the user's library. |
| P1 | The player overlay labels any selected URL ready when neither streaming nor preparing, even while `loadVideo` has no probe result or has failed. [Player overlay](../Sources/AirCillerApp.swift), [loadVideo](../Sources/StreamCoordinator.swift). | Derive headline, status and Play availability from a consistent state presentation. Check pending/failed probe fixtures and verify that neither says ready. |
| P2 | Apply in `TrackSettingsView` always writes the draft and invokes `applyTrackSettings`; that method re-prepares an active session without testing equality. [Tracks UI](../Sources/AirCillerApp.swift), [coordinator](../Sources/StreamCoordinator.swift). | Disable unchanged Apply or make it a no-op. Count preparations and verify Cancel/no-change preserve playback and settings; actual changes retain position behavior. |
| P2 | `statusRow` limits recovery detail to two lines without an expansion action. [Status UI](../Sources/AirCillerApp.swift). | Keep the recovery sentence and action visible; put longer technical detail in a disclosure. Check long Spanish/English messages at the supported minimum size. |
| P2 | Online subtitle search clears results on error; its empty-results branch always says "No hay resultados" even for a failed request. [OpenSubtitlesSearchView](../Sources/OpenSubtitlesViews.swift). | Separate loading, completed empty search, results and error. Exercise simulated network/authentication/configuration failures; preserve Settings recovery where applicable. |
| P2 | The main window minimum is 1080 x 760 points, the sidebar minimum is 290, and primary scroll indicators are hidden. [Window and mainContent](../Sources/AirCillerApp.swift). | Evaluate a compact native layout before choosing new minimum dimensions. Verify long content and essential actions at laptop/side-by-side sizes. Actual clipping has not been demonstrated. |
| P2 | Production engine-missing error text directs users to install a host engine, conflicting with the bundled-runtime policy. [AirCillerError](../Sources/AirCillerError.swift), [architecture](../ARCHITECTURE.md). | Explain how to repair an incomplete AirCiller installation; keep developer environment instructions in support documentation. Simulate the missing bundled-runtime case in both languages. |

## Unverified checks for the native prototype

- Timeline announcement as understandable time, library-row grouping, selected/current-item distinction and actionable error announcements in VoiceOver.
- Focus entering and leaving pairing/tracks sheets, Escape behavior, type-to-select, and interaction between global playback shortcuts and editing controls.
- Essential metadata with small text styles, contrast in active/inactive windows, and layouts with long track names or bitmap-subtitle explanations.
- The fixed-width tracks popover and dynamic player-height animation under compact windows and accessibility settings. Missing explicit Reduce Motion handling in custom code is a reason to test, not proof that the system response is wrong.

## Proposed delivery sequence

1. Command availability and truthful states, with meaningful regression coverage.
2. Recoverable library actions, unchanged track editing and actionable search/engine errors.
3. Native hierarchy, compact layout, optional contextual tracks/details and visual polish.
4. Keyboard, accessibility, localization and appearance verification in the running app, followed by any applicable playback/release checks.

Keep each change independently reviewable and avoid editing both playback packagers in one delivery. The design concept uses fictional data and simulated controls; it does not establish native usability, receiver behavior or release acceptance. Update this record as issues are reproduced, decisions accepted and changes actually verified.

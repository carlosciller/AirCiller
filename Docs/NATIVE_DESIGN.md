# Native macOS design for AirCiller

Design direction researched on 13 September 2026. This is guidance for future UI work, not a claim that the redesign or accessibility checks are implemented. Read the applicable section for the requested change. The [baseline audit](NATIVE_DESIGN_AUDIT.md) records observations, code findings and proposed work separately.

For future visual exploration, read the [reference dossier](NATIVE_DESIGN_REFERENCES.md) and [three proposals](NATIVE_DESIGN_PROPOSALS.md). These remain separate from the current playback work; no direction has been selected.

## Product brief

AirCiller helps someone choose a local movie, understand where it will play and control it on Apple TV. The interface should make the selected file, current item, destination and next available action unambiguous. Reliability, keyboard behavior, recovery and accessibility are part of design quality.

Preserve the existing native foundations: SwiftUI windows/settings/forms, `NavigationSplitView`, the AppKit playlist table, standard menus/panels, semantic colors and local data. Preserve the decisions in [the earlier interface review](STABILITY_REVIEW.md#interface-and-documentation). Keep macOS 14 support unless the task explicitly changes it. This design work does not authorize engine, playback-path, library-storage or network-service changes.

## Interaction decisions

### Window and hierarchy

- Keep system window chrome, resizing and active/inactive appearance. Choose a smaller supported window size through content tests; the current 1080 x 760-point minimum is an audit finding, not the new target. Essential controls and recovery must remain reachable at the declared minimum.
- Use the toolbar for a small set of frequent commands and a clearly named destination. Preserve menu equivalents and system overflow. Keep Play/Pause and Stop reachable when the main detail scrolls; do not make a bottom strip their only location.
- Keep Playlist/Recents selection separate from the currently playing item. A row highlight means selection; a distinct, labeled playback indicator identifies the active item. Single-click and arrow navigation must not start playback. Return/double-click follows the existing explicit activation behavior.
- Show a readable filename and make the complete original name available through selection details/accessibility. Do not rename files, discard identifying text or invent metadata. Mockup movie names are fictional fixtures, not a new online metadata feature.
- Put optional file/track information in a clearly scoped inspector or the existing tracks panel. Always name the item being edited. A selected-item inspector must not silently mutate the item currently playing. Preserve the draft, Cancel and Apply interaction for session-affecting settings.
- Keep codec/route/timing diagnostics under an explicit disclosure. Information needed to recover from an error remains visible. Avoid duplicated product branding, stacked translucent panels and decorative status cards competing with the movie.

Sources: [Windows](https://developer.apple.com/design/human-interface-guidelines/windows), [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), [Inspectors in SwiftUI](https://developer.apple.com/videos/play/wwdc2023/10161/).

### Commands, focus and data

Use the same availability rule for each button, menu command and shortcut. Keep cancellation available while preparation runs; a disabled Play action must not become active through a shortcut. Do not intercept typing, list navigation or sliders with global playback keys. Preserve focus after dialogs and distinguish keyboard focus, selection and the current item.

Apply should be disabled or a no-op when its draft equals the original settings. Explain the consequence of a real track change before applying it. Do not start a second preparation merely to close an unchanged panel.

For bulk removal from Playlist/Recents, prefer a named native Undo action that restores entries, order and saved progress. If recovery cannot be provided, use a specific confirmation for the destructive action. Removing a library entry must not delete its source movie. Keep ordinary reversible actions direct.

Sources: [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar), [The SwiftUI cookbook for focus](https://developer.apple.com/videos/play/wwdc2023/10162/), [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts).

### State and recovery

Derive a consistent UI presentation from existing analysis, preparation and receiver state. Review the affected state transitions before changing coordinator behavior; a visual state model is not permission to rewrite both playback paths.

| State | User-facing meaning | Appropriate action |
| --- | --- | --- |
| Empty | Choose or drop a movie | Open movie |
| Analyzing | The file is being checked; it is not ready yet | Cancel if the existing operation supports it |
| Ready | A supported file is ready to prepare/play | Play, or choose destination when none is available |
| Preparing | Work is in progress on this movie | Cancel/Stop; no duplicate Play |
| Connecting / awaiting receiver | A request was made, confirmation is pending | A supported cancellation or recovery action |
| Playing / paused | State reported by the active receiver | Matching Pause/Resume, seek and Stop |
| Error / unavailable file | Explain what failed and whether the current item is affected | Existing recovery: locate file, choose destination, retry or open settings |

Do not label a failed probe ready or a failed subtitle search empty. Reserve "No results" for a completed search with zero matches. A command ACK is not receiver progress; UI playback state is not proof of physical picture, sound, HDR or Atmos. Keep the [playback evidence rules](../.agents/skills/airciller-development/references/playback.md).

Show determinate progress only for measurable work; otherwise name the phase. Do not invent remaining times or animate a simulated success. Recovery text should say what happened and what can be done, with technical detail expandable/copyable. Missing bundled-engine guidance should direct users toward repairing their AirCiller installation, not installing a host engine.

Sources: [Progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators), [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts).

## Visual and accessibility system

- Use system font roles, semantic foreground/background styles and SF Symbols appropriate to the action. Keep essential filenames, states and settings readable; compact technical metadata must not become the smallest text simply to fit a layout.
- Use the user's accent color and system sidebar/control sizing. Establish hierarchy with grouping, spacing and a small number of type roles before custom color or materials.
- Use native materials for their intended surface roles. If a newer system offers Liquid Glass, prefer supported system controls and availability-checked enhancements, with a native macOS 14 fallback. Do not raise the deployment target or layer glass over every content area for a cosmetic change.
- Verify light/dark and active/inactive appearance, another accent, Increase Contrast, Reduce Transparency and Reduce Motion. Measure contrast where drawing/styling is custom; semantic API names alone do not prove readable output.
- macOS does not provide iOS Dynamic Type. Semantic SwiftUI fonts alone do not establish user-scalable text. Test system accessibility zoom/text needs and choose an explicit macOS text strategy when the content requires one.
- Give icon-only controls action names and expose meaningful values: a timeline should communicate elapsed/total time, not an unexplained fractional value. Communicate selection, current item, destination and disabled state. Announce phase/error changes without flooding VoiceOver on every progress tick.
- Test the real native accessibility hierarchy and keyboard/VoiceOver workflows. Framework controls are a useful foundation, not proof of accessible behavior. Keep alternatives to hover, drag and gesture-only actions.

Sources: [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Make your Mac app more accessible to everyone](https://developer.apple.com/videos/play/wwdc2025/229/).

## Acceptance and implementation order

1. Address the audit's command/state/recovery issues in separate focused changes. Reproduce each issue first. Playback-affecting fixes retain their existing local and Apple TV gates; a design label does not exempt them.
2. Prototype the hierarchy and track-editing flow with fictional content. Include empty, ready, preparing, playing, paused and recoverable-error states. Keep selection independent from playback and Apply unavailable for an unchanged draft.
3. Implement the accepted direction using the existing native components, then test the following matrix. Prototypes demonstrate simulated interaction only; native behavior, accessibility and performance remain unverified until exercised.

| Check | Observable acceptance |
| --- | --- |
| Primary task | The user can identify selected file, active item, destination, current phase and next action without opening diagnostics. |
| Keyboard | Open/select/activate/pause/stop/edit tracks/return to library works without a pointer; Space/arrows inside text or selection controls do not trigger unrelated playback commands. |
| VoiceOver | The same flow has useful labels, groups, values and focus return; no function depends only on hover, color or drag. |
| Resizing | At the declared minimum, normal size and full screen, all essential actions and recovery text are reachable; sidebar/inspector visibility does not remove functionality. |
| Localization | Spanish and English, long filenames, long track names and incomplete metadata fit without lost meaning. |
| Appearance | Light/dark, active/inactive and the accessibility settings above retain legibility and understandable state. |
| Adverse state | Empty library, absent receiver, failed probe, missing file, failed/empty subtitle search, long preparation and disconnect have distinct, actionable presentations. |
| Data and tracks | Bulk removal provides the chosen recovery behavior: Undo restores entries, order and progress, or a specific confirmation clearly states the consequence. Cancel preserves the original track draft; unchanged Apply causes no preparation; real changes retain the documented position behavior. |
| Compatibility | New APIs/symbols have verified availability and a tested macOS 14 path. No unsupported OS claim from testing only a newer system. |

Record scenario, version/commit, platform, input, action, observation and limitation. Use synthetic/private fixtures as appropriate; keep raw movie names, receiver identities, screen captures and diagnostic data out of public artifacts. Run the [contribution gate](../CONTRIBUTING.md#minimum-validation) for the actual change and keep [release readiness](../.agents/skills/airciller-development/references/release-readiness.md) separate from visual acceptance.

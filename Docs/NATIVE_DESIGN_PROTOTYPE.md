# Mac essential native prototype

13 September 2026. The maintainer selected **A. Mac essential** from the [shared comparison](NATIVE_DESIGN_PROPOSALS.md). This record describes a separate SwiftUI experiment for a future version. The current AirCiller playback work remains independent.

## Scope and artifact

The local design-task deliverable contains `AirCiller Design.zip`, the three Swift source/test files, a build script and a usage note. Its bundle identifier is `local.airciller.design.mac-essential`. The prototype lives outside this repository; no executable prototype source or binary is part of the documentation PR. Future integration must start from the then-current AirCiller baseline and the accepted behavior, not by replacing application files with the prototype.

The window uses a native sidebar list, a session detail area, an optional tracks inspector, toolbar commands, menus, sheets, SF Symbols and a timeline slider. System/light/dark appearance and example phases are available from the scenario menu. Newer transport styling is guarded at macOS 26, with a standard prominent-button fallback.

The [comparison's fictional fixtures](NATIVE_DESIGN_PROPOSALS.md#shared-comparison) and an in-memory model drive the interface. Preparation advances only through the prototype's next-phase command. Opening, locating and retrying use examples. There is no media engine, actual file picker, network client, receiver discovery or real playback. The app has the sandbox entitlement and no network or user-file access entitlements. It is locally ad hoc signed for inspection, without distribution notarization or installation into Applications.

## Evidence collected

| Layer | Observed result | Limit |
| --- | --- | --- |
| Local build | Swift 6.4, SDK 27.0, arm64 deployment target macOS 14.0; strict concurrency and warnings-as-errors passed. | Deployment targeting is not a runtime test on macOS 14 or an Intel build. |
| Local model | Twelve deterministic tests passed. | The model uses fictional state and no AirCiller engine code. |
| Artifact | Ad hoc signing and strict signature verification passed before archiving. | This is a local prototype, not a notarized release. |
| Native UI | On macOS 27.0 build 26A428, inspected light/dark appearance at 960 x 650, with the inspector open/closed and active/inactive presentation. Native accessibility text exposed the window, sidebar, toolbar, menus and labelled slider. | Compact resizing, complete accessibility and older-OS acceptance remain pending. |
| Initial state | Costa al amanecer was active at 42:18 of 1:42:00; La última estación was selected; the tracks inspector was closed. | Fictional playback, with the no-receiver notice present. |
| Native interactions | Selected another row without changing the current movie or position; paused/resumed with the menu shortcut; opened/cancelled the example sheet; toggled the inspector; changed/cancelled audio; applied audio then cancelled preparation, restoring audio and position; cancelled analysis and observed Play disabled; explicitly activated another analyzed selection. | These exercised the prototype model, not AirCiller's engine. |
| Receiver / physical | No receiver contacted and no physical playback performed. | No AirPlay, audio, subtitles, HDR or Dolby Vision claim. |

The tests cover selection without interruption, explicit activation, analysis/cancellation, playback and seek bounds, editable-track validation, unchanged Apply, cancellation rollback, paused-state preservation, missing-file identity and recovery, and an unavailable receiver after opening/analyzing another example. Static review also checked command enablement and focus restoration. These checks do not replace native interaction tests.

The initial command-line build exposed a State macro plugin missing from the installed tools. The prototype explicitly resolves SwiftUI's existing State property wrapper through a typealias. Tools and SDK installations were not changed. Signing takes place in temporary storage because File Provider can add Finder metadata to bundles in synced storage; the deliverable is then archived without those attributes.

## Pending native acceptance

The Mac briefly locked during inspection; native checks resumed after the maintainer unlocked it. Two visible label-layout issues were corrected and the final build was reopened to verify them. Remaining work before accepting the composition for implementation:

1. Verify compact window resizing and all states at narrow sizes. The attempted resize did not change the observed window, so it is not counted as validation.
2. Exercise the remaining native error/recovery and timeline interactions; their model tests already pass.
3. Check complete keyboard traversal, focus restoration and VoiceOver announcements. The observed shortcuts and accessibility tree cover only part of this acceptance.
4. Check reduced motion/transparency, contrast and larger text before accepting the composition for implementation.

The design direction is selected; native acceptance remains incomplete. Apply the [design acceptance criteria](NATIVE_DESIGN.md#acceptance-and-implementation-order) and refresh the [source audit](NATIVE_DESIGN_AUDIT.md) before future integration. Use AirCiller's normal tests and physical evidence requirements for the behavior actually changed. The prototype provides no release-readiness evidence for AirCiller.

# Bug fixes after 0.14.0

Work in progress, 21 September 2026. Base: published 0.14.0,
commit `2780d4af8d7ac892686c0fcda595b08706c4ffe7`. No new release or installed-app
replacement is implied by this record.

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

## Next checks

- Minimum window size and long inspector content, with English and Spanish.
- Focus and draft preservation after Cancel and Apply.
- Repeated commands and recovery, scoped to each reproduced failure.

The manual SDR HLS audio timing repair remains separate. Do not mark it fixed
or widen either packager as part of this menu correction.

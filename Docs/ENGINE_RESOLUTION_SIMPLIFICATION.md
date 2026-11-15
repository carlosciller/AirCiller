# Bundled engine resolution: 15 November 2026

## Scope and validation selection

The preceding UI-builder cleanup is merged as PR #61. This change removes host
runtime discovery from ComponentManager, AirPlayController and Executables.
BundledEngine owns executable lookup. Missing or non-executable bundled tools
remain unavailable; neither Homebrew nor an old runtime marker supplies a
replacement. The packaged marker and ACBundledEngineRequired remain intact.

Standalone media fixtures can opt into explicit FFmpeg/ffprobe paths using
the test-only compilation flag documented in TESTING.md. Existing injected
executable parameters and bundle-based benchmark fixtures remain supported.
No production build enables the new flag. No Python override is introduced.

Required validation: resolver regressions in production and standalone-test
builds, component discovery with missing bundled tools, explicit-path media
regressions and the complete strict local gate. Compare unchanged packaging,
helper, engine and dependency inputs against the baseline.

No receiver session is selected: both playback routes retain the same bundled
executable paths, command construction, runtimes and delivery behavior. The
change removes unused host fallback in ordinary app builds, which already set
ACBundledEngineRequired. This is not fresh evidence of Apple TV output.
Do not replace or launch the installed application.

## Results

Focused resolver checks passed: bundled paths take precedence, unavailable
executables fail closed, ordinary builds ignore explicit test environment paths,
and opt-in standalone builds accept executable absolute paths while rejecting
relative or missing paths.

The first focused compilation could not write the default compiler cache; it
passed using the project's existing module cache. The first full gate stopped
at formatting in the new resolver test, before code regressions. Formatting was
corrected without changing behavior.

The final complete local gate passed with pinned Python 3.13.15 and Node
24.19.0: `AirCiller local checks: OK`. This includes the new resolver cases,
component discovery without bundled tools, the explicit pinned-engine artwork
probe, existing preparation/control regressions, strict Swift 6 compilation,
bundle signatures and Python packaging checks. No capture device was opened.
The built application executable contains no test-override environment keys.

Production Swift changes remove 86 lines net. The existing Executables entry
point remains as a forwarding call to avoid unnecessary changes in consumers.
There are no changes to command builders, the Python helper, engine/dependency
pins, resources, Info.plist or the production build script.

The installed app, credentials and playback session were untouched. No release,
installation or GitHub mutation was performed. Next step: review and integrate
this bounded change; AirPlay control simplification remains separate work.

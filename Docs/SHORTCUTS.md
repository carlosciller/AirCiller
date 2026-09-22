# Apple Shortcuts integration

Unreleased work, 22 September 2026. This record distinguishes implemented source
from actions discovered and executed by macOS. No release or daily-app update
is implied.

## Actions

| Action | Effect |
| --- | --- |
| Open Movie | Opens and analyzes a saved movie without starting playback |
| Send Movie to Apple TV | Selects a unique receiver and starts normal preparation; optionally starts from the beginning |
| Add Movie to Playlist | Adds a movie once, leaving its existing position and current playback alone |
| Pause AirCiller | Sends an explicit pause request to the active session |
| Resume AirCiller | Sends an explicit resume request; cannot start a stopped movie |
| Stop AirCiller | Cancels the pending shortcut handoff and stops current preparation or playback |

The actions run in the foreground in the main app. The app registers its one
window-owned coordinator at startup. There is no separate extension, playback
session, Finder Quick Action, Services entry or permanent background process.
Action names, parameters, results and errors have English and Spanish strings.
Local device authentication follows Apple's App Intent policy.

Open and Send reject work while another movie is being prepared or played, or
while a pairing/conversion decision is pending. Add can run during playback.
Sending with more than one discovered receiver requires its exact, unique name;
the action does not choose the first receiver arbitrarily. Device selection uses
the existing authorization method, clearing the previous receiver's state.

The normal audio-conversion and pairing prompts remain in AirCiller. Successful
handoff means preparation has started, not that the television has shown a frame.
Pause and resume results acknowledge a command request, not physical output.
Once preparation has been handed to the app, use Stop AirCiller to cancel it.
Canceling an earlier waiting shortcut cannot stop a newer UI-selected movie.

## File contract

The first integration accepts readable, regular saved movie files with the same
container extensions as the app. It uses `IntentFile.fileURL`; it never reads
`IntentFile.data`, copies a large movie or uploads it. Data-only inputs, remote
URLs, missing files, directories, temporary files and inputs removed when the
shortcut finishes are rejected with an instruction to save the file first.
Symbolic aliases into the temporary directory are rejected as well.

Security-scoped access is retained while the movie is selected or referenced by
the in-memory library. Unreferenced handles are released on the next action or
when the process exits. The library still persists file paths, not security-scoped
bookmarks. Reopening a protected-folder file after relaunch remains an explicit
acceptance case; do not claim persistent access from the in-process check.

## Build boundary

`build.sh` emits Swift constant values and invokes Xcode's
`appintentsmetadataprocessor` against that same binary and its final bundle
identity. Production and full candidate builds fail before modifying a staged
bundle when that tool is unavailable. Metadata must contain nonempty action and
version files; generated data must not be substituted by a handwritten manifest.

Command Line Tools on the development Mac do not include the processor. The
explicit `./Scripts/check.sh --without-shortcuts` mode runs local regressions and
builds `AirCiller Test.app` with `AIRCILLER_NO_SHORTCUTS`. That candidate has
`ACShortcutsAvailable=false` and no discoverable actions. Playback Checks also
excludes the App Intent definitions. Neither is Shortcuts runtime acceptance.

Building in CI with full Xcode is an alternative to installing Xcode locally.
Download the complete bundle: do not attach metadata from a different compiler
to a local executable. Uploading the branch, installing Xcode, publication and
daily-app replacement are separate authorized operations.

## Evidence and remaining checks

Local simulated-target regressions exercise file rejection, idempotent adding,
busy sessions, explicit controls, ambiguous receivers, bounded discovery,
canceling a waiting handoff and stale UI generations. The real coordinator
regression checks library limits and preserves its synthetic playback state.
These checks use no receiver or private movie.

The build-tool tests use synthetic constants and a mocked processor to verify
arguments and failure handling. A local Swift 6.4 compiler emits real constants
with the macOS 14 target. The six wrappers have also passed strict typechecking.
This does not prove actual metadata extraction or discovery in Shortcuts.

The complete limited local gate passed on 22 September, including strict Swift 6,
all local/simulated regressions, localization, public-content checks, signature
verification and the UI-only candidate build. It contains 155,968,590 logical
bytes, under the 165 MB limit. The actual production sources, including the app
entry point and intent/controller integration, also passed a separate strict
typecheck without stubs or test compilation flags. That typecheck is now included
in the limited gate. The normal gate fails early without Xcode's processor.

The installed 0.14.0 executable's SHA-256 is unchanged. Neither the candidate nor
an Apple TV session was launched. Native access was retried once after independent
source work and again reported a locked Mac with failed automatic unlock. CI
compilation and manual unlock were requested; neither was assumed.

## Xcode candidate verification (22 September)

The maintainer authorized uploading the working branch and building a test
candidate in GitHub, without publication or daily-app replacement.
[Run 35754339418](https://github.com/carlosciller/AirCiller/actions/runs/35754339418)
passed the full default gate and packaged the isolated candidate from commit
`2984cdaa33bb708ed5beb1350a422e8c5ca93fb1`, using Xcode 26.6 (17F113) and Swift
6.3.3. The duplicate push run was deliberately canceled; it was not a failing
test run. The Vision cancellation message in the successful run belongs to its
expected cancellation regression.

Apple's generated catalogue contains the exact six actions, their AirCiller
module identities, discoverable/foreground settings, Shortcuts localization table
references and the expected parameters. Open/Add take a required movie file;
Send also exposes an optional receiver name and the start-from-beginning option,
which defaults to false. The catalogue has no automatic App Shortcuts. The
English and Spanish tables are present. These are package observations, not a
claim that the Shortcuts editor has displayed or executed the actions.

Packaging now checks the final catalogue as well as Swift's extracted types.
Twenty focused regressions cover missing actions, wrong module/identifier,
hidden or background-only actions, changed titles/tables, parameters and summary
references. The stricter validator also passes against this real Xcode output;
its synthetic fixtures are never used to package an app.

The downloaded ZIP passed its SHA-256 check:
`1a62b20f848a99979062d7147249ff35827312c13b7e7102c895987cae059644`.
Its original ad hoc bundle signature passed strict verification. An independent
local copy adds the existing, unchanged credential service and uses the already
configured local signature and client entitlements. Compiled function bytes,
metadata, resources and third-party frameworks were preserved; checksum and
symbolic-link comparisons supplement the directory comparison. The local copy's
complete signature passes and it measures 154,408,405 logical bytes within the
165 MB budget. The engines and playback sources were not changed by this step.

Candidate evidence is retained under `.build/shortcuts-ci-35754339418/`, with the
download, original bundle, prepared local bundle and CI/verification logs kept
separately. No app was launched, real AirPlay credential read, pairing performed
or receiver session started. The installed 0.14.0 executable remains unchanged.

Still required before acceptance:

- Find all six actions in Shortcuts in English and Spanish, with correct names,
  parameter summaries, app identity and icon.
- Open/Add/Send with the app closed and already open; verify the same visible
  playlist and player, with no unwanted Finder registration.
- Protected-folder input across relaunch, large saved files without copying,
  and clear errors for temporary/data-only inputs.
- Missing/ambiguous receivers, receiver changes, pairing, conversion refusal,
  cancellation and a subsequent UI action without a stale handoff.
- Run Pause/Resume/Stop from Shortcuts over direct MP4 and HLS, observe captured
  Apple TV output, and check stop, replay and app closure. Ordinary playback-runner
  passes alone do not establish that macOS dispatched a Shortcut.

Only the exact approved digital Apple TV source may be captured. Mac and iPhone
cameras and microphones remain prohibited.

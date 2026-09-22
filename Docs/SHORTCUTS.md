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

## Native registration check (22 September)

After the maintainer unlocked the Mac, the prepared local CI candidate opened
on macOS 27.0 (26A428). Its running executable path matched the prepared copy;
its SHA-256 remained
`84e8c107f923d59a2b72a8cb0ad33fb058695f19392c1acc7406de4f7fe2a616`.
The installed 0.14.0 executable remained unchanged. The final source/build-tool
[CI run 35756208556](https://github.com/carlosciller/AirCiller/actions/runs/35756208556)
also passed at `cbad590748ec10011da81fa28b531631bb6acf3f`.

**Discovery failed.** Searching for AirCiller in the actual Shortcuts editor
returned no actions, including after quitting and reopening Shortcuts. macOS
Launch Services registered the exact candidate with its `link-enabled` flag,
but `linkd` reported `Failed to generate bundleIdentity` and
`Unable to get teamId` for that running candidate. The local signing certificate
has no Apple Team ID. The scoped diagnostic is retained privately beside the
candidate as `runtime-linkd.log`.

This establishes a registration blocker for this candidate and signing setup;
it does not establish that every macOS version requires paid membership. Apple's
[developer account guidance](https://developer.apple.com/help/account/basics/about-your-developer-account#enable-a-personal-team-in-xcode)
describes free Personal Team development signing through Xcode. A genuine Apple
development-signed, non-receiver comparison is the next investigation if the
maintainer authorizes that setup. Its success and public-distribution suitability
are not established. Do not fabricate a Team ID, edit generated metadata, reset
system indexing or change Keychain protections to make discovery pass.

A different signing certificate would also be rejected by the existing
[credential service](CREDENTIAL_SERVICE.md), which deliberately pins the current
local certificate. Any subsequent credential-service migration needs separate
planning and validation; it is not an automatic part of the discovery test.

No Shortcut action was executed. No Apple TV playback, capture, pairing or
credential reset was performed. The six actions and their receiver cases remain
unaccepted despite successful compilation and metadata validation. One empty,
clearly named QA shortcut was created in the editor; no Finder action, automation
or system shortcut was enabled.

## Development-signing setup (22 September)

The maintainer authorized trying Xcode with a free Personal Team. Xcode 27.0
(27A266a) was installed from Apple's Mac App Store. Only the built-in macOS
platform was selected; optional iOS, watchOS, tvOS and visionOS downloads were
left off. Additional external-agent access was not enabled. An explicit
`DEVELOPER_DIR` check found `appintentsmetadataprocessor`; the globally selected
Command Line Tools path was retained.

The maintainer completed Apple account sign-in. Xcode recognizes a free Personal
Team, but its certificate manager lists no signing certificates and the Apple
Development creation item is disabled. This does not establish a paid-membership
requirement: Apple's [macOS development-signing guidance](https://developer.apple.com/forums/thread/763141)
explicitly permits Personal Team development signing. The cause of the disabled
item remains unverified.

After the maintainer explicitly authorized creating development credentials,
automatic signing in the isolated project succeeded. Xcode created a development
key and certificate, and the resulting signature verifies through Apple's
development certificate chain with a real TeamIdentifier. No trust setting was
changed. The initial sandboxed signature check could not resolve certificate
trust; the same strict/deep verification outside that tool sandbox passed.
This follows [Xcode's signing workflow](https://help.apple.com/xcode/mac/current/en.lproj/dev60b6fbbc7.html),
not a change to AirCiller's local signing or credential-service policy.

The isolated app contains one no-input intent and a visible in-memory counter.
It has no AirCiller coordinator, network/file permissions, credential access,
AirPlay code, camera or microphone access. The ordinary coordinator was
deliberately excluded because it starts receiver discovery and can read
credentials during startup.

The same project was checked in the native Shortcuts editor under two signing
setups, retaining the ad hoc bundle separately:

| Check | Ad hoc | Apple Development |
| --- | --- | --- |
| Action discoverable in Shortcuts | Yes | Yes |
| Native dispatch | Communication error; counter stayed at 0 | Cold launch incremented counter to 1; a second run with the app open incremented it to 2 |
| Scoped `linkd` evidence | `Unable to get teamId` | Accepted application and mediator connections; runtime policy allowed |

The source and generated intent catalog were unchanged. Xcode also enabled the
configured hardened runtime for the development-signed build. This comparison
establishes that the development-signing setup permits this probe's discovery
and dispatch on the tested Mac. It does not establish public distribution,
universal OS behavior, AirCiller's six actions or receiver playback. In
particular, the probe's ad hoc discovery succeeds, so the earlier candidate's
missing search results must not be attributed solely to its missing Team ID.

Evidence, source, project, baseline bundle and build logs are retained privately
under `.build/shortcuts-signing-probe/`. The existing QA shortcut now contains
only this diagnostic action, with its result display disabled after the first
successful run. No Finder action or automation was enabled.

AirCiller's installed 0.14.0 executable, signing identity and pinned credential
service remain unchanged. Integrating a different signer into the real app
requires a separately reviewed credential-service migration; simply re-signing
the candidate would fail the current caller check. No receiver playback,
pairing or capture was performed during this comparison.

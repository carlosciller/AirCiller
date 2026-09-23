# Apple Shortcuts integration

Unreleased work, updated 23 September 2026. This record distinguishes implemented source
from actions discovered and executed by macOS. No release or daily-app update
is implied.

Current acceptance: the complete development-signed candidate passes the normal
local gate. All six actions have appeared and executed in native Spanish
Shortcuts. Open/Add chains, cold Send, and Pause/Resume/Stop on HLS and direct
HDR have been checked. Public-package signing and the remaining file/localization
cases are not yet accepted; this is not a released feature.
See [the latest native check](#foreground-results-and-hls-controls-23-september).

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
Action names, parameters, descriptions and errors have English and Spanish strings.
Local device authentication follows Apple's App Intent policy.

Successful actions return an empty result. AirCiller is already visible, so a
separate success dialog adds no necessary information and can delay a chain in
Shortcuts. Errors and the app's pairing/conversion decisions remain visible.

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

## Complete candidate native check (23 September)

This records the earlier candidate. The follow-up below supersedes its unresolved
chain and HLS-control checks, without replacing the retained evidence.

An isolated source snapshot of `47e45d7` passed `./Scripts/check.sh` with Xcode
27, strict Swift 6 and warnings-as-errors. Its separate full Test build contains
Apple-generated metadata for the six actions and measures 156,107,449 logical
bytes, below the 165 MB limit. Its executable SHA-256 is
`f9d3c6f53429024d9a06d42b1c1876c85ff958407d40cdca3d762c66831b2f86`.

The candidate uses a genuine Apple Development signature and its own read-only
credential service, built from the unchanged source with the same signer as the
candidate. The existing synthetic integration test passed: rebuilt clients
could reuse a synthetic item, invalid callers and a tampered service were
rejected, and the synthetic item was removed. The old signing configuration and
credential service were not replaced. The maintainer separately authorized the
new service to read existing AirPlay credentials; this run did not independently
verify a real read or observe a Keychain approval prompt.

Launch Services selected an older Playback Checks bundle for the shared test
identifier, despite the new candidate being correctly registered and accepted
by `linkd`. That older bundle has no App Intents. After explicit authorization,
five competing test registrations were temporarily withdrawn without removing
their files. `NSWorkspace` then selected only the current candidate, `linkd`
indexed its exact catalogue, and reopening Shortcuts exposed all six Spanish
actions with the distinct test icon. No source, generated catalogue, SDK setting
or Team ID was changed, and no system-wide indexing reset was performed.

Native execution used an existing synthetic, saved 60-second H.264/E-AC-3 MKV:

- Open cold-launched the exact candidate, analyzed the movie and left it ready
  without starting playback. A subsequent warm Open also reached `perform()`
  and returned, confirmed by the scoped App Intents log.
- Add executed independently twice. The visible playlist gained one entry,
  retained the two preceding test entries in order and did not add a duplicate.
- An Open → Add chain completed Open but did not dispatch Add before it was
  canceled. Independent Add succeeded afterward. The cause remains unresolved;
  this is not a passed multi-action check. A comparison with result presentation
  disabled was being prepared when Shortcuts accessibility calls began timing
  out. It was not executed.

The candidate was closed normally and all five test registrations were restored;
the API again lists all six copies, with the candidate currently selected. The
shared identifier remains a development-environment collision risk. No permanent
registration cleanup was applied. Raw evidence and the incomplete comparison
remain private under `.build/shortcuts-development-4mGppm/` and in the existing
temporary QA shortcut. No Finder Quick Action or automation was enabled.

Still unverified: English native discovery, protected-folder access across
relaunch, large-file handoff, multi-action behavior, real credential-service
access, and Send/Pause/Resume/Stop through Shortcuts over both playback paths.
Discovery saw a receiver during this run, but no receiver playback, pairing or
digital capture was started. The installed app and its preferences remain
unchanged. Development signing does not establish public distribution or
notarization readiness.

## Foreground results and HLS controls (23 September)

On the unchanged earlier candidate, Add → Open completed with both Show When
Run options enabled, but took about 17 seconds between the first result and the
next invocation. With result display disabled, the interval was under 0.1 second.
This comparison narrows the observed wait to result presentation; it does not
prove the cause of every earlier Shortcuts accessibility timeout.

The six foreground actions now return empty results instead of success dialogs.
The controller, authorization policy, errors, conversion decisions and both
packagers are unchanged. A regression calls all six real intent wrappers with a
simulated target, checks the absence of dialog/snippet/media results and verifies
that a missing-session error still propagates. It fails on the old implementation
and passes on the correction. The complete strict `./Scripts/check.sh` gate and
the separate development candidate build pass.

The corrected candidate executable is
`f5ad7cdb372add1d8b4be98d9e92f89f38d9c4e93f4131fbba94ac0722d1c8f3`;
it measures 156,089,105 logical bytes, below the 165 MB limit. Strict signature
verification passes and the isolated credential-service executable is unchanged.
Native Shortcuts no longer shows the unnecessary success-display option. The
saved Add → Open chain completed twice; the later warm run took about 44 ms
between actions. This is a bounded interaction observation, not a startup
benchmark or a promise for every Mac. Pausing without a session produced the
expected localized error.

The maintainer confirmed the receiver was awake and free. Native Send selected
the explicitly named receiver and began the saved H.264/E-AC-3 synthetic clip
from the beginning. Native Pause and Resume each received a separate
receiver-originated state notification. The approved digital capture recorded
the moving test pattern and non-silent audio before and after the pause, with
silence during the paused sample window. Stop then returned the app to Ready,
retained its position and received the receiver's stop confirmation. No pairing
or Keychain approval dialog was observed. These results use the real Shortcuts
dispatcher, not the internal playback runner.

One additional receiver pause coincided with the capture helper's 90-second
shutdown, after the successful Resume and before the explicit Stop. That event
is retained separately; its cause has not been proven. The Stop confirmation
was outside the capture window and is receiver/UI evidence only.

Private evidence includes `native-chain-dialog-comparison.log`, the before/after
wrapper regression, both build logs, and `native-hls-shortcuts.log` under the
isolated development snapshot. Capture `native-ui-final-capture-fzcskg10` has a
complete, source-verified manifest and its frame analysis. No Mac/iPhone camera
or microphone was used. The installed executable and production preference
export still match their preservation baselines. No release or installation was
performed. English native discovery, protected-folder access across relaunch,
large-file handoff and distribution acceptance remain separate checks.

### Direct HDR controls and cold Send

The same corrected candidate then opened the existing 60-second HEVC Dolby
Vision/E-AC-3 5.1 sample. Its integrated English subtitle was selected for that
movie through the inspector, without changing default-language preferences.
Playback was started from AirCiller's ordinary Play button; the active process
served a prepared `movie.mp4`. This establishes the direct route, not native
Send with a preferred subtitle.

Pause, Resume and Stop were each executed from the native Shortcuts editor.
Both pause and resume had separate receiver-originated notifications, and the
app's labels/buttons reflected those states. The capture contains movie frames,
non-silent audio and integrated subtitle cues after resume. Sampled subtitle
text was checked against the original subtitle track. The explicit Stop received
confirmation, returned AirCiller to Ready and was followed by the receiver's
screensaver in the capture. The source movie was not changed.

Finally, the candidate was closed and its absence verified before invoking Send
on that saved HDR file from Shortcuts. The exact corrected candidate cold-launched,
completed discovery and started at zero. Default subtitles remained off, so this
case uses the normal HLS HDR path, not the preceding direct-subtitle route.
Captured movie frames and non-silent audio establish output. Quitting the app
during playback exited its process and returned the capture to the receiver's
screensaver. There were no later audio measurements in that final window; the
record does not substitute that absence for measured silence. No test app,
AirPlay helper, preparation process or credential-service process remained.

These two additional captures are `native-ui-final-capture-cypjggkt` and
`native-ui-final-capture-1_ldc1nl`, with complete, exact-source-verified manifests,
frame analyses and scoped native logs. No camera/microphone or default-input
fallback was used. No pairing or Keychain password dialog appeared in any of
the three runs. The default subtitle-language key remains absent in the test
domain; the production preferences, installed executable and old signing/service
hashes still match their baselines. The test candidate is closed. Its registration
and the two clearly named QA shortcuts are retained for follow-up.

These are sampled digital-output and native-dispatch checks on this Mac/receiver.
They do not certify physical HDR/Atmos rendering, speakers, every movie, public
distribution, English native discovery or protected-folder persistence. Native
Send with an automatically preferred subtitle remains distinct from the direct
controls verified above. No release, version increase or daily-app replacement
has been performed.

# Private remote control

Private integration installed after directed acceptance checks. The maintainer
authorized the separate home-server service, tunnel, ChatGPT plugin and local
installation. This work does not authorize a public release.

## Architecture and privacy

ChatGPT sends bounded MCP commands through a separate Secure MCP Tunnel to the
home server. The MCP endpoint listens only on loopback. AirCiller makes outbound
authenticated HTTPS long-poll requests to the relay; the Mac opens no listener.
The relay and tunnel are separate user LaunchAgents, independent of other
services. They require the server user's logged-in session.

The HTTPS agent listener resolves its configured hostname to an actual local,
non-internal interface, preferring IPv4. macOS may return loopback first for its
own Bonjour name; that address cannot serve the other Mac. The listener selects
only an address both returned for that name and present on a non-internal local
interface. It never falls back to all interfaces or an unrelated address. If no
usable address exists, startup fails. The MCP endpoint remains loopback-only.

The client verifies a pinned certificate, hostname, validity and signature.
DNS comparison is case-insensitive. AES-GCM also authenticates each command with
an installation-specific context. Owner-only configuration files contain the
separate tokens and key. Secrets never appear in repository files or literal
command arguments. No global certificate trust or router configuration changes
were made.

Only commands and necessary titles, tracks, progress and errors cross this
connection. Movies, audio, subtitle contents, local paths and AirPlay credentials
do not. Media metadata is untrusted data, never an instruction.

The native gateway calls the existing StreamCoordinator on the main actor.
There is no second player, library or AirPlay engine. Normal playback and the
credential service remain independent of the opt-in client.

## Controls and operation identity

The closed vocabulary covers status, library search, play, pause, resume, stop,
next, seek/skip, configured receivers, tracks, synchronization, language
preferences, conversion decisions, operation status and cancellation. It
provides no shell, arbitrary file access or general system settings.

Start with status for the current session ID. Reuse an operation ID when
retrying an uncertain mutation. A delayed request for a different session is
rejected. Conflicting identifier reuse is rejected, not executed. New requests
expire within 60 seconds; operation storage is bounded. Long operations can
be queried and cancelled only while they still own the current preparation.

Library identifiers are opaque and stable for this installation. Ambiguous
searches return candidates. Track identifiers belong to the current session.
Receiver selection is limited to configured devices and does not pair a new one.
Synchronization uses the same bounds as the app: audio ±5 seconds, subtitles
±10 seconds. Language preferences explicitly state session or persistent scope.

Conversion approval belongs to a specific pending decision and selected track.
The caller can approve one item or equivalent later playlist episodes. Compatible
original audio stays preferred. Stop, including a receiver-reported Stop, ends
playlist conversion consent. A later prompt after Stop is not permission to
silently approve a new decision.

Acceptance is not receiver confirmation. Status distinguishes preparation,
conversion decisions, fresh receiver state and errors. Receiver confirmation
does not establish physical picture or sound. Declining conversion is a completed
decision, not an operation waiting forever for playback.

## Activation and availability

Provisioning puts the private client configuration in the user's Application
Support directory. Settings shows Private control only when that configuration
is present. The integration defaults off. Disabling it stops its connection and
invalidates old control sessions without stopping a movie.

The optional lifecycle LaunchAgent can open and normally close the installed
AirCiller app independently of its playback connection. Its three tools are
openApp, closeApp and appStatus. They use a separate bounded relay queue so the
app and lifecycle agent cannot consume each other's commands. A fixed native
helper uses NSWorkspace and NSRunningApplication; callers cannot supply a path,
application identifier or executable. Normal termination uses the app's existing
progress-saving and playback cleanup. The helper checks the private-control
preference before acting; disabling private control also disables these tools.

The Mac must be awake with the user logged in. System sleep, a closed lid,
logout and restart awaiting authentication are different conditions. The agent
does not wake or unlock the Mac. An unavailable agent returns unknown/timeout,
never an assumed success. No password injection or security/energy-setting
changes are part of this integration.

Example requests:

- “Busca Edgerunners y enséñame sus episodios.”
- “Abre AirCiller” / “Cierra AirCiller” / “¿Está abierta AirCiller?”
- “Continúa el segundo episodio donde lo dejé.”
- “Pausa” / “Reanuda” / “Adelanta treinta segundos.”
- “Pon el audio japonés y los subtítulos en castellano.”
- “Retrasa los subtítulos medio segundo.”
- “¿Por qué está esperando?”
- “Cancela la preparación que acabas de iniciar.”

## Provisioning and removal

For lifecycle control, compile PrivateRemote/Lifecycle.swift using Swift 6
strict concurrency and warnings-as-errors, then run install-lifecycle.mjs with
the compiled helper's absolute path. The installer uses the existing Node
runtime and provisioned owner-only client configuration. It prepares the
user LaunchAgent local.airciller.private-lifecycle; bootstrap it in that user's
GUI domain. It requires no administrator privileges. Keep the configured Node
runtime available while this service is installed.

To remove lifecycle control, boot out only that LaunchAgent and move its plist,
lifecycle-agent.mjs and lifecycle-helper into a recovery directory. Preserve
client.json and the playback connection unless removing the whole integration.

PrivateRemote/provision.mjs prepares the relay configuration, certificate and
relay launch configuration. save-runtime-key.mjs accepts the separate restricted
key through hidden local entry and verified SSH stdin without printing it.
provision-tunnel.mjs prepares the tunnel launch configuration. Use the actual
tunnel executable, not a wrapper that changes energy behavior. Inspect generated
configuration privately before activating either service.

The server service labels are local.airciller.private-relay and
local.airciller.private-tunnel. Their plists live in the user's LaunchAgents
directory; private files live in the owner-only AirCillerPrivateRelay Application
Support directory. Daily use requires no administrator privileges. The dedicated
runtime key has only Tunnels Read + Use permissions, with no model permissions.
No new paid contract was enabled; this is not a promise about future pricing.

To disable reversibly:

1. Turn off Private control in AirCiller and disconnect its ChatGPT plugin.
2. Unload only the two named user LaunchAgents.
3. Move their plist files and their private support directory into an owner-only
   recovery folder. Do not touch another connector's files or services.
4. Move only the Mac's AirCiller/PrivateRemote support subdirectory into a private
   recovery folder. Keep the rest of AirCiller's library and preferences.
5. Revoke the dedicated runtime key and delete the dedicated tunnel only when
   rollback is no longer required.

## Evidence checkpoint (2026-10-20)

Local checks cover authentication, argument bounds, ambiguous titles, duplicate
and stale commands, conversion identity, terminal decisions and encrypted
delivery. The cross-process HTTPS test uses the real coordinator with isolated
preferences. It rejects the wrong certificate, recovers from a dropped poll,
accepts uppercase DNS names and verifies authenticated Stop/session rotation.
It opens no television or media session.

The separate home-server relay and tunnel are installed and the tunnel reports
ready. AirCiller Private is connected in ChatGPT. Live status, library and
configured-receiver queries reached the candidate. A separate ChatGPT conversation
returned the actual pending conversion and all ten episode candidates; the
maintainer also confirmed that query from the iPhone.

Following explicit approval, ChatGPT resolved a conversion decision with
equivalent-episode consent. Preparation started. The first attempt timed out
waiting for the receiver. A cached retry confirmed progress, followed by a
receiver-reported Stop. Digital captures showed a screensaver and silence, so
those runs do not pass audiovisual acceptance. Capture interference remains a
hypothesis, not an established cause; no timeout relaxation or engine workaround
was applied.

In the subsequent control test without concurrent capture, ChatGPT paused the
episode at 200.15 seconds. The maintainer locked the Mac. The OS reported a
logged-in session and screen lock before the next command. ChatGPT resumed
through the plugin; a fresh receiver observation reported playing at 218.75
seconds while the OS still reported screen lock. No app UI or login password
was used for this command.

ChatGPT then selected the next episode. The earlier receiver Stop had cleared
conversion consent, so the next decision remained pending. ChatGPT cancelled
that exact operation by its original ID; the operation returned cancelled and
the session returned idle with no pending conversion.

These live observations belong to candidate executable SHA-256
8b2f383cf388d818f32b7b72ff35c406038690a9f4ade9444ac7989ac4d647ed.
The subsequent gateway-only correction marks declined conversions and idle track
edits terminal immediately. Its focused coordinator
and HTTPS regression passed, followed by the complete strict check. It does not
change either video packager.
The rebuilt candidate SHA-256 is
c7d3674503245524303746a8517fa6c8f4a24756b812561f290f34f81d5305bb;
it was reopened without playback and returned idle through the connected plugin.

The rebuilt candidate subsequently passed a directed digital-output check using
compatible original AAC audio. A graphics-subtitle preparation was cancelled
through the plugin to avoid an unrelated full OCR run. With capture ready before
playback, the first film was visible. The plugin's Next command opened the next
playlist item, whose picture was also captured. A plugin seek reached a known
dialogue cue; its English subtitle was visible in the digital frame. Turning
subtitles off returned the track as unselected and fresh receiver progress
continued. Plugin Stop returned idle and rotated the session.

The completed capture contains 125 video frames and 442 digital-audio samples,
with peak sampled RMS -16.83 dBFS. This establishes sampled picture, non-silent
digital audio and the identified subtitle cue, not physical speaker output or
whole-film reliability. These commands used the connected MCP tools in Codex;
the earlier pause/resume and conversion checks used the separate ChatGPT chat.

Capture lifecycle remains a QA caveat: one receiver pause coincided with capture
shutdown, and starting a new capture during playback was followed by receiver
Stop. Preparing capture before starting playback produced the successful run.
This correlation is not a proven root cause or a reason to change the player.
Private frames and sample reports remain in the ignored private-remote build
directory; they are not publication assets.

The separate ChatGPT chat then selected the sole English subtitle on the stopped
second film and independently read back selected=true with original AAC audio
unchanged and phase=idle. It did not start playback.

The final continuity check used a fresh explicit approval. In the separate
ChatGPT chat, Play selected episode 2 at its saved position and resolved the
exact conversion decision with equivalentEpisodes=true. A fresh receiver
observation confirmed progress. ChatGPT then issued Next without Stop: episode 3
prepared with awaitingConversion=false, and no new approval was sent. Digital
frames showed both episodes; audio samples within five seconds of the reviewed
frames had peak RMS -24.15 dBFS and -13.22 dBFS respectively. The completed,
source-verified capture contains 155 frames and 364 audio measurements. ChatGPT
Stop then returned idle with no pending conversion. Capture was stopped too.

The complete strict check passed on the unchanged executable identified above.
After playback stopped, the candidate was closed and installed locally. Its
installed executable hash matches the validated candidate, and deep strict
code-signature verification passes. The running process was verified at the
daily installation path, not the build path. The library and saved positions
remained present; Settings showed private control enabled and Connected. A fresh
plugin status returned the new idle session after relaunch.

The previous daily bundle is retained at
`.build/private-remote/rollback-before-private-mcp/AirCiller.app`, outside the
registered test-storage cleanup roots. The older pre-existing rollback bundle
was not deleted. To restore, stop playback and quit AirCiller, preserve the
private candidate, and replace the daily bundle with this retained copy. The
private client can also be disabled independently in Settings.

This is a private local installation retaining the existing version label,
not a public release or a Sparkle-update acceptance claim. No tag, release or
public deployment was created. The capture-lifecycle caveat above remains
documented; the successful run kept capture ready across episode transitions.

References: [Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels),
[playback evidence](PLAYBACK_CHECKS.md), [Shortcuts boundary](SHORTCUTS.md).

## Lifecycle checkpoint (2026-10-21)

The native helper compiled with Swift 6 strict concurrency and warnings as
errors. Six focused Node tests passed, covering the authenticated command
contract, expiry, tamper rejection, independent queues and duplicate identity.
The full project check also passed. No playback packager or engine changed.

The lifecycle user service is installed and the existing private plugin's
catalog was refreshed to include its three tools. In the actual ChatGPT test
conversation, appStatus returned running, closeApp followed by appStatus returned
closed, openApp followed by appStatus returned running, and the playback status
then returned idle. The installed app's process ID changed independently,
confirming a real restart. No movie was started and no capture device was used.

The OS still reported an unlocked logged-in session during this check. Neither
the keyboard shortcut nor the menu action through UI automation established
lock. Locked-screen acceptance was therefore still pending at this checkpoint;
the earlier playback-control check did not replace it.

The home server's previous relay sources are preserved in its private
recovery-before-lifecycle directory. Removing the lifecycle LaunchAgent and
restoring those three sources reverses this extension independently of the
existing playback plugin. The daily app bundle did not need replacement.

## Locked lifecycle acceptance (2026-10-23)

After the maintainer manually locked the Mac, macOS reported
`IOConsoleLocked = Yes` before the test. Through the connected AirCiller Private
MCP tools in Codex, appStatus returned closed, openApp returned running and an
independent status query agreed. The installed app's process appeared at its
expected path. closeApp then returned closed, a fresh status query agreed and
the process was absent. The OS still reported screen lock after both operations.

The observations were recorded at 11:37:39 and 11:38:00 UTC. No movie, UI control,
password entry, capture device or system-setting change was involved. The tested
installed executable remains
`c7d3674503245524303746a8517fa6c8f4a24756b812561f290f34f81d5305bb`.
The private operation record is retained under `.build/audit-20261023/`.

This validates the installed lifecycle path while the Mac is awake, logged in
and screen-locked. It is not a new iPhone-originated command, a wake/unlock test,
or deployment validation of the separate relay/lifecycle source corrections in
the October review. Those source changes have not been installed.

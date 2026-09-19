# Mac essential integration

19 September 2026. Base: AirCiller 0.13.0 (4d749e5). This is the production
integration of the maintainer's selected **A. Mac essential** direction, not a
replacement of the application with the earlier simulated prototype.

## Scope

- Keep the existing native Playlist table, fixed row rhythm, drag/autoscroll and
  keyboard reordering. Library selection remains separate from the loaded movie.
- Replace the large video-preview canvas and stacked status cards with the named
  session, transport and concise track summary. The toolbar keeps Play/Pause,
  Stop, destination, Open, diagnostics and the inspector available while scrolling.
- Use a native optional inspector for the current movie's audio/subtitle draft.
  Unchanged, stale, busy or different-file drafts cannot apply. Actual changes
  still use the existing coordinator operation; no packaging implementation changes.
- Show full filenames in the session and selected-item detail. Keep diagnostics
  in the explicit information popover. Use system materials, fonts and colors.
- Share playback-command availability across the coordinator, buttons and menus.
  Analysis has an observable state and replacement identity. Unknown authorization
  must still allow the first Play; an actual check, pairing or conversion decision
  blocks duplicate commands. Stop cancels pending work.
- Reserve unmodified arrows for native controls. Command-arrow seeks ten seconds;
  Option-Command-arrow seeks thirty seconds. Space retains Play/Pause and
  Option-Command-Up/Down retains Playlist reordering.
- Confirm bulk library removal. Distinguish a subtitle-search error from a
  successful empty result. Missing-engine guidance directs users to reinstall
  the bundled application.
- Give internal GUI builds the same [test icon](TEST_APP_ICON.md). Production
  artwork is preserved exactly. Internal builds have no update feed or file
  associations and are not a data sandbox.

Both packagers, subtitle preparation, HTTP delivery, runtime locks and credential
allowlists are unchanged. The deferred SDR HLS manual-audio-offset defect is not
repaired here.

## Acceptance record

Focused deterministic checks cover command availability, finite seek bounds,
unchanged/changed/reverted/stale track drafts, missing-engine recovery and the
production/test icon representations. The strict whole-project gate passed for
the first integrated candidate, including the native Vision tests, localization,
large-file server checks and the Swift 6 warnings-as-errors build. Native
interaction review subsequently found a defect; there is no release-readiness
claim yet.

The first local gate stopped at a sandbox-restricted pip-tools cache. After its
cache/network permissions were granted, the second reached unchanged Apple Vision
tests but could not create a pixel buffer inside the sandbox. These are retained
as failed attempts, not ignored checks. The first unrestricted run then caught a
Swift binding error in the pairing sheet. An explicit binding corrected that
error; the subsequent unrestricted run passed without weakening tests or engines.

The first actual native review loaded a synthetic movie without starting playback
and confirmed its full title, duration, original-audio summary and transport
accessibility values. Opening the inspector then caused an AppKit constraint
update loop and terminated the test app on macOS 27. Keeping its content present
while hidden passed the local gate but did not fix the native crash; that failed
attempt is retained. Moving the inspector inside the split view's detail, as in
the approved prototype, removed the crash but exposed vertical cropping across
the columns. A finite inspector viewport now keeps the editor's intrinsic height
from resizing the enclosing split layout.

The final viewport candidate passed opening, editing, Cancel, reopening and
native half/quarter-window tiling with a long synthetic filename. Cancel restored
the +0.00 audio draft, and unchanged Apply remained disabled. The header, session,
transport and pinned inspector footer were visible in the compact window; the
editor exposed a native scroll area for remaining options. Spanish dark appearance
and the real accessibility tree were inspected. No playback was started during
this UI review. The installed 0.13.0 application is unchanged.
These native observations used the final interface sources before the candidate's
version metadata advanced to 0.14.0 (61); no interface or playback code changed
after those observations.

A separate source review found that Stop could be disabled during the bounded
post-analysis network wait even though automatic playback was still pending.
The correction now starts an observable, UUID-owned wait before analysis ends;
Stop cancels it, and stale task cleanup cannot clear a newer movie's wait. The
focused strict Swift test passes cancellation, replacement and single handoff.
Updates are also deferred during that wait. The final whole-project gate passed
for 0.14.0 (61), including this correction and the finite inspector viewport.
Signing and the existing 165 MB budget also passed. This is local evidence, not
an installation or a substitute for receiver acceptance.

Native review was interrupted again when the Mac locked. English/light appearance
and the remaining interactive library checks are still pending. The idle GUI
candidate was terminated by its verified process identity before rebuilding the
separate playback-check app; the two internal apps must not run together. The
six-case receiver batch was built from the frozen 0.14.0 (61) inputs.

Its first live attempt stopped at capture readiness, before credentials, fixture
preparation or playback. The approved source was verified and its capture session
started, but no initial frame arrived within 20 seconds. Cleanup completed and
the daily application stayed unchanged. The capture tools are byte-identical to
the successful 0.13.0 run; this failure does not establish a media or UI defect.
A separate bounded capture-only retry reproduced the same verified-source,
running-session, no-frame result. Its report and the first attempt are retained
separately. Both stopped before credential access or playback, and no checker,
helper or sampler processes remained afterwards. There were no further device
attempts, wake requests, pairing, permission changes or alternate inputs. The
six playback cases remain unverified for this candidate. No control-only fallback
can pass this gate.

Native checks must exercise compact and normal layouts, the named inspector,
unchanged Apply, cancel, selection/activation, keyboard, English/Spanish and
appearance. Shared command changes also need current direct MP4 and HLS receiver
checks. Earlier physical confirmations and the prototype are not fresh evidence
for this candidate.

No new format support, end-to-end speed, physical HDR/Atmos, complete VoiceOver,
macOS 14 runtime or whole-movie-reliability claim follows from this interface work.
Publication and daily installation remain separate gates.

The implementation is a release candidate, not an accepted release. Keep GitHub
Latest and the daily installation at 0.13.0 until the outstanding interface review
and current receiver/captured-output checks are complete. Package signing,
release-tag CI, public assets and the real Sparkle update are not established by
the local check result.

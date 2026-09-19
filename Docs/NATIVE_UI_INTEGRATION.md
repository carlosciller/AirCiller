# Mac essential integration

19 September 2026. Candidate: AirCiller 0.14.0 (61), based on 0.13.0
(`4d749e5`). The selected direction is [A. Mac essential](NATIVE_DESIGN_PROPOSALS.md#a-mac-essential).
The [native prototype](NATIVE_DESIGN_PROTOTYPE.md) is the composition reference;
its simulated playback is not application or receiver evidence.

## Design correction

The first integration retained the sidebar, session detail and optional inspector,
but diverged from the selected design: wider columns, a borderless Play button,
controls above the timeline, stacked track information and an expanded editor.
Its successful build and initial interaction checks did not establish visual
fidelity. That limitation was identified during the subsequent source comparison.

The revised source restores the prototype's 225-point ideal sidebar, 265-point
ideal inspector, 30-point content margins, title treatment and balanced session
area. The timeline is above the circular Play/Pause button and is limited to
440 points. The primary button uses the native prominent glass style on macOS 26
and later, with a standard prominent-button fallback. Ready, busy and active
sessions have distinct presentations; selection details adapt between a row and
a column. Optional chapter controls move to a second row when space is limited.

The inspector uses a grouped form with Audio and Subtitles first. Synchronization,
audio output and additional subtitle options are initially collapsed. Real track
names, file import, OpenSubtitles, timing/reset controls and explanatory text are
retained. Selected conversion and unsupported-track warnings remain visible.
The named header and Cancel/Apply footer stay outside the scrolling form. Long
header filenames have a three-line limit; the full name remains available in
help, accessibility and the main session/selection details.

Production adaptations preserve the existing AppKit Playlist table, fixed row
rhythm, drag/autoscroll and keyboard reordering. The fictional fixtures and
scenario controls are not part of the app. Diagnostics remain in an explicit
popover. Internal GUI builds use the [test icon](TEST_APP_ICON.md); production
artwork is unchanged. Internal builds have no update feed or file associations
and are not a data sandbox.

## State and safety

- Library selection does not load a movie. Activation and playback remain explicit.
- Buttons, menus and shortcuts share command availability. Unknown authorization
  permits the first Play; an actual check, pairing or conversion decision prevents
  duplicate commands. Unmodified arrows remain available to native controls.
- Stop cancels analysis and the UUID-owned pending automatic start. An obsolete
  task cannot clear a replacement movie's wait; updates are deferred during it.
- A nonfatal error does not remove active transport or preparation cancellation.
  Error detail remains visible. The session header derives normal phases from
  session state, so a library message cannot replace the playback label.
- Unchanged, stale, busy and different-file track drafts cannot apply. Changing
  audio tracks retains the original-output default. Cancel discards the draft.
- Bulk removal requires confirmation. Subtitle-search errors are distinct from
  completed empty results. Missing-engine recovery directs users to reinstall
  the bundled app.

Neither packager, subtitle preparation, HTTP delivery, runtime locks nor
credential allowlists change in this delivery. The deferred SDR HLS manual-audio
offset defect remains outside its scope.

## Local and native evidence

Earlier strict checks passed, but actual inspector opening then exposed an AppKit
constraint-update crash. Keeping hidden content mounted did not fix it. Moving
the inspector into the split view's detail removed the crash but exposed vertical
cropping. The retained finite inspector viewport bounds its content without
resizing the enclosing columns. Failed attempts remain recorded separately; those
earlier builds are not the final design candidate.

The following observations used the revised candidate on macOS 27 with synthetic
local media. They did not start television playback:

| Scenario | Observed result |
| --- | --- |
| Spanish, dark appearance | Empty and ready states showed the expected hierarchy, including a long filename. |
| Compact inspector | A 265-point inspector in an 871 × 574-point window opened without a crash or cropped controls. Audio and subtitle menus were visible. |
| Track draft | Synchronization opened; changing audio to +0.05 seconds and cancelling discarded the change. Reopening retained +0.00; unchanged Apply stayed disabled. |
| English, light appearance | Ready state and the long-name inspector were visually inspected. Selecting an external subtitle marked the draft changed; Cancel left it unapplied. |
| Library keyboard | Up/Down changed selection without loading a movie. Option-Command-Up/Down reordered it, and the original order was restored. |
| Bulk removal | Cancelling the clear confirmation preserved both synthetic Playlist entries. |
| Restoration | Spanish and dark appearance were restored after the language/appearance checks. |

The drag automation produced no reorder, so it does **not** establish new drag
validation. Complete keyboard/focus traversal, VoiceOver, accessibility appearance
settings and execution on macOS 14 remain outside these observations. The compact
check above does not certify every state at the declared 720 × 520 minimum.

Review also corrected unknown authorization being presented as active waiting,
nonfatal errors hiding active controls, chapter-row overflow at narrow widths,
and library status text replacing the session header. Deterministic phase and
command tests cover pending/active/error precedence and cancellation ownership;
draft and recovery tests remain in the strict gate. The final header-copy and
localized close-label adjustments followed the native review. The final
whole-project gate then passed, including strict Swift 6 compilation, Vision,
localization, simulation and distribution-content checks. The signed local app
measured 155,694,108 logical bytes against the existing 165 MB limit. A preceding
sandbox-restricted pip-tools cache attempt is retained separately. This final
gate does not substitute for native checks of changed labels or receiver output.

## Receiver and release status

The previous six-case receiver attempt stopped at capture readiness, before
credentials, fixtures or playback. The approved digital source was verified and
its session started, but no initial frame arrived within 20 seconds. One bounded
capture-only retry reproduced that result. Both reports and cleanup results are
preserved; neither attempt validates playback or demonstrates a media defect.
No wake, pairing, permission changes, alternate capture source, camera or
microphone was used. No test or capture processes remained afterwards.

A later capture-only attempt again received no frames. The maintainer then
confirmed the Apple TV had been asleep and woke it. The next bounded readiness
check received a verified frame of its Home screen and closed cleanly. It used
the same approved source and unchanged capture tools, without credentials or
movie playback. All preceding failures remain in the private record.

The rebuilt 0.14.0 (61) checker completed the seven-case batch on 20 September
2026. Executable SHA-256:
`8dcf6a930b1614e63445ec9fde6f44ff7a2c6e0faea722a9b27a7dfbbdb619fd`.
Source inputs, capture tools and the installed app remained byte-identical
throughout the run. The original six-case configuration was retained separately.

| Current case | Receiver/control evidence | Captured digital output |
| --- | --- | --- |
| Direct HDR MP4 with selectable subtitles | Progress, pause/resume, seeks and Stop/cleanup passed. | 29 sampled frames, confirmed motion, 29 cue detections and non-silent audio. |
| HLS with subtitles | Same bounded controls passed. | 28 frames with 28 cue detections and non-silent audio. |
| HLS without subtitles | Same bounded controls passed. | 28 frames, no expected cue and non-silent audio. |
| Direct subtitle replacement | Applied through the coordinator and cleaned up. | Initial and replacement cues were separately detected with motion/audio. |
| HLS track changes | Subtitle replacement, original-audio change and subtitles off passed. | Four phases retained motion/audio; the audio tone changed from 880 to 440 Hz, and cues disappeared only in the Off phase. |
| Cancel preparation | A running FFmpeg preparation stopped, followed by three seconds without delayed playback. | Negative case; no audiovisual-output claim. |
| Playlist transition | Receiver completion led to loads 1 then 2 exactly once, followed by cleanup. | The next clip supplied eight sampled frames and non-silent audio without subtitles. |

All selected checks completed without evidence gaps; all checker/capture/helper
processes closed. The real playback window was also inspected read-only during
the direct case: its phase, format/track summary, moving timeline, elapsed/total
times, circular Pause and both ten-second skips matched the chosen design.
This Mac-window observation is separate from the Apple TV capture above.

Six-minute pauses, bitmap OCR and physical remote scenarios were not repeated:
their preparation, remote protocol, buffering and sleep-prevention paths are
unchanged from the recorded prior versions. No new physical HDR/Atmos, speaker,
remote, whole-movie or startup-speed claim follows from this interface work.

The public ad hoc build measured 155,616,379 logical bytes. Its full ZIP and delta
from official build 60 produced identical extracted bundles, including modes,
symlinks and signatures. Sparkle signatures for the feed, full archive and delta
passed verification. The production identity, artwork and update key are
unchanged; internal-test and local credential-service markers are absent.
Sparkle's identity warning reflects the different code hashes in these two ad hoc
signatures. This is not Developer ID signing or notarization, and the actual
update remains a separate check.

The normal GUI candidate reopened at the intended default size with the final
header and named inspector. Before its first Stop/replay/quit attempt could
begin, the Mac locked. The Play action returned a locked-session error; that
attempt did not establish playback. Native interaction stopped and the maintainer
was asked to unlock manually. The separate capture showed only a screensaver.

After the maintainer confirmed manual unlock, the normal candidate completed
Play, central Pause, Resume, toolbar Stop, Play again and Command-Q. Its executable
SHA-256 was `727c1ac5b4534de81c49ca68f3693a524dd1252fa5c052629e22ba9240c87c98`.
The Mac showed the correct phase and control availability at each step. Stop
returned to Ready with the saved position; playing again continued near second
21, not from the beginning.

A separate 90-second capture from the same approved Apple TV digital source
confirmed motion and non-silent audio in the initial, resumed and replayed
intervals. Seven sampled paused frames were stationary and all 17 paused audio
measurements were silent. Inspected Stop and post-quit frames showed the
screensaver without the movie player. The final post-quit interval had no audio
measurements, so it does not establish measured silence. Scoped process checks
found no remaining app, AirPlay helper, FFmpeg or capture processes. No original
movie, daily library or installed app was changed by these checks.

Code, native interaction and the selected receiver/output acceptance are complete
for these frozen executable inputs. Package signing is recorded above. Exact
commit/tag CI, public-asset verification and the real Sparkle installation follow
the separate [distribution procedure](../DISTRIBUTION.md); none is inferred from
a local build or these playback observations.

# Continue Season candidate

Delivery 1 of the local-library improvement goal. No version bump, publication,
installation, tvOS application or playback-engine replacement is included.

## Expected behavior

- Selecting a season shows a visible Continue Season action with the chosen
  episode's retained title and saved position. Selection alone never plays.
- Choose the first episode not marked watched in persisted manual Playlist order.
  Do not sort by filename, infer episode numbering or prefer a later partial item.
- Use the same resume-position policy as ordinary library playback. Queue progress
  takes precedence over Recents; legacy missing progress can use Recents. A completed
  episode explicitly marked pending starts at zero. Invalid saved positions use zero.
- All watched means Season Completed, not an automatic restart. The existing Play
  and per-episode restart actions remain available. Missing files use existing
  recovery instead of silently advancing to another episode.
- Pending preparation/analysis/recovery disables continuation. If its target is
  already streaming, do not reload it; resume a paused session through existing
  controls. An explicit action on a different target uses ordinary movie loading.
- Preserve library order, watched state, source filenames and originals. Do not
  create another storage format or silently change audio conversion consent.

## Validation selection

Local regressions: pure selection/resume policy and the real coordinator's busy,
missing-file, current-session and explicit-load decisions. Native checks: real
season selection, visible episode/position, completed state, EN/ES and narrow window.
Full strict contribution gate once on the final executable candidate.

The existing packagers, server, AirPlay helper/controller and pinned runtimes are
unchanged. Reuse applicable route evidence only after comparing inputs. A short
targeted season-action receiver check is required for the new playback entry point;
do not repeat codec, OCR, long-pause or throughput campaigns. Receiver state is not
proof of audiovisual output. Any missing device observation remains pending.

Results will be recorded with the tested candidate. The installed app remains
untouched; use only isolated builds and synthetic/private test preferences.

## Delivery 1 evidence, 2 November 2026

- Pure selection/resume regression passes, including manual ordering, watched and
  legacy state, completed seasons, queue-zero precedence and invalid positions.
- Production-coordinator regression passes for explicit load at 42 seconds,
  preparation and conversion-decision guards, no duplicate in-flight load,
  no restart of an already-playing target, and completed-season availability.
- The first headless missing-file assertion incorrectly expected `hasError`.
  The existing library action presents a native Locate/Cancel alert instead.
  Its failure log remains `season-continuation-coordinator-first-failure.log` in
  `.build`; recovery acceptance was moved to the actual native interaction,
  not treated as a passing headless recovery test.
- The real production view in a UUID-isolated UI app shows the correct episode
  and 00:42 position. Selecting another, completed season shows Season Completed,
  with Continue Season disabled in its context menu. Clicking Continue on a missing
  episode presents Locate/Cancel naming that file. Cancel retains the same target
  and progress; no analysis or receiver starts. English/dark and Spanish/light
  were inspected. The 720-point-wide window clamps to a 572-point outer height
  for its declared minimum content; the long title wraps and the action is visible.
  System appearance/language were not changed. Coordinate resize attempts did not
  establish a resize; the isolated harness's explicit narrow option supplied the
  tested minimum instead. Spoken VoiceOver and older macOS remain unverified.
- The strict contribution gate passed in `.build/season-continuation-full-check.log`.
  The later change to the opt-in UI harness's window-size flag was independently
  strict-compiled and format-checked. It does not affect ordinary app inputs;
  no identical ordinary-app rebuild was run for that test-scene-only adjustment.

### Directed receiver and digital-output check

The authorized batch used one HLS fixture, compatible original E-AC-3 stereo and
selectable English text. The synthetic manual queue was a watched Episode 1,
pending Episode 3 at 15 seconds, then Episode 2. The actual coordinator selected
Episode 3, and the receiver confirmed position 15. A lower Recents position of
4 seconds did not override queue progress. Pausing and using Continue Season
resumed the same session at receiver position 23.04; the load count stayed one,
including an additional action while already playing. Stop released the runtime.

| Digital observation window | Frames | Expected subtitle | Central motion | Test pattern | Non-silent audio |
| --- | ---: | ---: | ---: | ---: | ---: |
| Continued episode | 14 | 14 | 14 | 7 | 34/35 |
| Resumed episode | 14 | 14 | 14 | 7 | 35/35 |

Both windows meet the unchanged sample-count, coverage and cue/audio/motion
criteria. The approved exact Apple TV source supplied a complete source-verified
manifest. These are sampled digital observations, not physical speaker, surround,
HDR, frame-accurate synchronization or whole-episode claims. No camera or microphone
was used. The batch is `.build/playback-checks/capture-run-season-_jeu67lk`.

The coordinator and selection-policy hashes in its identity report match the
current production source. The check executable hash was
`d22ed46f27c06437292b52c39b91804016cc12ad908e3b93e577aa292c324ba0`.
The custom check compiles current production sources with the established
playback-check isolation; it is not an alternative playback implementation.
Bundled helper bytes match the current script. Engine, Python dependencies and
Sparkle inventories match the accepted ordinary build, including symlink entries
without traversal. The initial recursive Framework comparison hit symlink loops;
the separate non-following inventory supersedes that comparison. Reports remain
in `.build/season-check-resource-parity.json` and the original comparison logs.

Both media packagers, HTTP server, AirPlay controller/helper and pinned runtimes
are unchanged from 0.18.4. Library admission and finite resume values still feed
the same existing `loadVideo` entry point; the new selector is independent of
the probed video format. The prior direct-route resume evidence is retained on
that input comparison; no new direct-HDR, codec, OCR or long-pause claim is made.

All check apps and capture processes closed, and the television was released.
The daily app was already closed and was not opened for this batch. Its installed
executable is unchanged:
`7468f56c611c0f9293c4c19f978d226d202a92414f3f22494a06c4bf41754466`.
No installed library, credential store or original media was intentionally written;
native/coordinator checks use separate UUID domains and the receiver harness
restores only its established test domain. A daily-preferences checkpoint for
later goal stages is retained locally, not claimed as a before/after comparison
for this already-completed stage. No publication, installation or service
deployment occurred.

### Test storage

Initial admission failed at 13.2 GiB. Ten obsolete MP4 intermediate variants from
an earlier header audit were explicitly inventoried and retired through the
existing completed-run cleaner. Their base and failure-reproducer clips retain
their original hashes; reports, current tools, recovery and the two Aether/spatial
experiments were preserved. The manifest is in the private
`run-retired-audit-5vq11ple` directory under `.build/playback-checks`.
An idle, regenerable test module cache was also removed after compilation had
finished. These are disposable outputs, not original movies. The successful
receiver run pruned its own fixture and auxiliary compiled payload through the
same guard. The 12 GiB limit was not changed.

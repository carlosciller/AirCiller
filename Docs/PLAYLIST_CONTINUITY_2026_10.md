# Playlist continuity investigation

## Reported failure

The maintainer watched episode 1 of Edgerunners after approving an audio
conversion. At its natural end, Apple TV returned to its menu with a connection
warning. AirCiller was waiting for another audio conversion approval for episode
2. The exact warning text and incident timestamp have not been established from
retained logs. Inspection of the idle installed app confirmed Japanese DTS-HD MA
5.1 selected for episode 2, with E-AC-3 conversion. The user described AC-3.

## Findings from the coordinator

Before this candidate, `playbackFinished()` called `cleanupRuntime()` before
loading the next item. That stopped AirPlay, shut down the HTTP server and ended
the idle-system-sleep assertion. `loadVideo()` also called Stop and reset audio
output to Original. Approval changed only the current output mode. Consequently,
the next unsupported audio track prompted again, before stream preparation
reacquired the sleep assertion.

This establishes a gap in application sleep protection and explains repeated
approval. It does not establish that macOS actually slept during the reported
incident. The power log inspected during investigation showed its latest sleep
and wake entries on 19 October, ending in a full wake at 09:15:48 local time.
No event has been correlated to the reported episode transition. The specific
cause of the television's connection warning remains unverified.

## Candidate behavior

Conversion consent is held only in memory and retained across automatic playlist
advancement. It matches input codec, profile, channel count, speaker layout,
sample rate and precision. Unknown channel information does not qualify for
automatic reuse. Compatible audio stays Original. FLAC eligibility and manual
audio delay are checked again for each episode.

The approval dialog explains the session scope. Stop, an independently selected
title, clearing the playlist, receiver Stop, cancellation and playlist completion
clear the relevant consent. A separate assertion covers automatic analysis and
the approval wait, handing over to the stream assertion once preparation starts.
An inactive session ignores duplicate natural-end notifications.

These assertions inhibit idle system sleep. They do not change display settings
or promise to prevent explicit Sleep, lid-close sleep or critical battery sleep.

## Validation

- Strict Swift 6 consent checks pass: equivalent episode, compatible original,
  changed codec/channel treatment, FLAC route restrictions and reset.
- Real coordinator tests pass for natural advancement, duplicate completion,
  sleep protection during the transition and release on Stop.
- Full local suite and strict application build passed. The extended plan model
  passed its focused check after its update. The final receiver-check app built
  with strict Swift 6 and warnings as errors.
- Real coordinator tests also passed receiver failure and invalid-episode
  analysis, including release of transition sleep protection.
- One live playback used two identical 60-second H.264/24-bit PCM stereo MOV
  fixtures. The first conversion was explicitly approved through the ordinary
  coordinator method. A seek near the end was followed by receiver-reported
  natural completion and exactly one automatic advance. Episode 2 reused the
  approval without another dialog. Both digital capture windows contained moving
  video and the expected 880 Hz audio. Episode 1 showed the expected subtitle;
  episode 2 correctly had none. This proves the consent/transition mechanism,
  not physical speaker layout or a reproduction using the original DTS movie.
- Private evidence:
  `.build/playback-checks/capture-run-playlist-consent-zd4nte99/report.json`.
  Controls recorded `[1, 2]`, no unverified checks and successful cleanup. The
  output evaluator reported no gaps in either sampled window.
- Earlier attempts stopped before playback: the generated MKV lacked declared
  channel layout, then the installed app was still open. The idle installed app
  was closed for isolation and reopened afterwards with library progress intact.
- Installed AirCiller has not been replaced. No release is authorized by this goal.

## Draft release note

Continue watching a season without approving the same audio conversion for every
episode. AirCiller remembers your approval for the current playlist session,
keeps compatible audio unchanged, and keeps your Mac awake while preparing the
next episode. Stopping playback clears that approval.

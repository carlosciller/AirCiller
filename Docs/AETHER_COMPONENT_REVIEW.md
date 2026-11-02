# Aether component review for AirCiller

Delivery 6, 2 November 2026. Decision: do not add AetherEngine or a new playback
dependency to this candidate. Retain the focused TrueHD object-rendering result
as research. Production integration requires the checks below.

## Source and experiment identity

Reviewed the retained checkout at commit
`2d1e83bfb56a12e2c44f3a8de55e0f033836fa14`, its spatial audio source files,
Package.swift, license and both ignored local experiment reports:

- `.build/spatial-airplay-experiment-20261101/report.json`: synthetic PCM/APAC
  transport, explicitly no Aether integration or TrueHD object decoding.
- `.build/truehd-atmos-aether-20261102/report.json`: actual TrueHD object render,
  exported media, source-video conservation, local decoding, receiver controls
  and sampled digital output. This is a different, stronger audio experiment;
  it must not retroactively upgrade the earlier synthetic result.

The checkout's Package.resolved differs from its committed state. Use the
experiment's retained resolution, not the checkout's nominal defaults: FFmpegBuild
3.12.1 (`9c87af0`), LibDovi 2.1.0 (`0d7cce1`), LibTrueHD 3.1.0 (`73bee84`),
SMBClient 0.3.1 (`e636c2b`). Nothing was resolved or upgraded during this review.

## Components and applicability

| Component | Concrete evidence | AirCiller decision |
| --- | --- | --- |
| TrueHD object decoder and spatial renderer | The real-source experiment produced a 12-channel, 24-bit/48 kHz 7.1.4 bed. All four height channels had signal; up to 13 elevated objects were reported. Exported video decoded to the same 649 source frames | A real research capability beyond AirCiller's channel-only TrueHD-to-FLAC option, but not yet a production feature |
| PCM spatial transport | Local native decoding found 12 channels; receiver controls and sampled digital audio passed | The capture had two channels. It does not prove 12-channel HDMI routing, physical heights or Atmos indication |
| APAC encoder | The earlier synthetic APAC-v2 case completed controls and non-silent digital audio | Does not prove actual-source object preservation or physical Atmos through this AirPlay setup. APAC is an encoding step, not original-audio passthrough |
| AtmosOutputActivator | Its source restricts activation to HDMI routes and returns no local output ports on macOS. It follows an in-process host player/renderer | Not usable to control the receiving tvOS player's HDMI route from this macOS sender. Do not add a parallel silent player or a tvOS client |
| Whole engine, software video renderer, SMB and LibDovi | No new AirCiller incompatibility or measured preparation/startup gain established by these experiments | Do not duplicate the current engine, add unrelated network access or replace working video routes |

The object-render report records limiter use and a deepest reduction of 2.1 dB.
Rendering objects into a speaker bed is a changed presentation; lossless source
decoding does not make the complete render sample-identical to the original or
equivalent to a reference Dolby renderer. That independent comparison was not
performed. Do not market this result as bitstream TrueHD/Atmos passthrough.

## Production gate if this is pursued later

1. Establish physical output on the maintainer's actual HDMI/speaker chain;
   sampled stereo capture cannot replace that observation. No additional hardware
   session is run merely to repeat the known digital transport result.
2. Choose one optional decoder/render boundary; measure CPU, memory, preparation
   latency and app-size delta against the current channel-only path. The retained
   experiment establishes no comparative startup saving or shipping size budget.
3. Define explicit user consent and honest labels for rendering, limiter behavior,
   output layout and any lossy APAC encode. Keep compatible original audio first.
4. Validate cancellation, seeking, complete finalized output, both route-specific
   constraints and macOS availability. The reviewed object/APAC path requires
   OS 26 APIs; AirCiller still targets macOS 14. No silent fallback or floor raise.
5. Review the exact component's distribution requirements and pinned dependencies
   before incorporating code. The inspected engine license is LGPL-3.0 with its
   stated store exception; that is not clearance for every transitive artifact.

No component is adopted without those missing observations. This is an
evidence-led deferral, not a claim that spatial audio over AirPlay is impossible.
The valuable existing experiment is preserved; the lightweight installed app,
original files, credentials and current AirPlay architecture are unchanged.

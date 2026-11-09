# Isolated Aether comparison

**Research closed; whole-engine adoption parked.** See the
[closure decision](../../Docs/AETHER_PROTOTYPE_2026_11.md#decision-and-scope).
The 160-sample discrepancy also occurs in a reference without Aether, but its
exact cause and source fidelity remain unresolved. No receiver run is queued.
The commands below preserve reproducibility, not an instruction to resume work.

Research prototype, not an AirCiller feature or release candidate. It neither
installs an app nor contacts an Apple TV. It does not access credentials, capture
devices, the user's library, preferences or ordinary caches.

## Build and run

From the AirCiller project root, with Xcode installed at `/Applications/Xcode.app`:

```sh
zsh Prototypes/AetherComparison/build.sh
python3 -B Prototypes/AetherComparison/test_snapshot.py
python3 -B Prototypes/AetherComparison/compare.py /absolute/path/to/development/ffmpeg
python3 -B Prototypes/AetherComparison/compare.py /absolute/path/to/development/ffmpeg eac3
```

The explicit development encoder must provide libx264 and the selected AAC or
E-AC-3 encoder (AAC is the default). It generates only
a synthetic 27-second movie. AirCiller processing uses its pinned bundled engine.
The separate Aether checkout stays in `.build/dependencies/AetherEngine-7.62.0` at
`a1d2cab8281cbf06f5f459b05dad4653ad12559f`. Its only source addition is this host;
`engine-target.patch` adds its build target without modifying the engine code.
Retain the resolved dependency versions with each result. The tested resolution
is FFmpegBuild 3.14.0 (`2ff2238f6b65d7686e71c8aa9e45fa4e26f33e1d`), LibDovi 2.2.0
(`caff700968700467c089a3f38c8b4180620518b5`) and SMBClient 0.3.1
(`e636c2b2458930770932a36d311ec9d478575b90`). Optional traits are disabled; LibTrueHD
is removed from the resolved graph by SwiftPM. Do not silently update these pins.

Both local hosts compile in Swift 6 strict mode with warnings-as-errors. Aether's
own upstream target has its own settings and currently emits warnings. A passing
host build is not a warning-free audit of the whole upstream engine.

## What is compared

`Host.swift` instantiates the full AetherEngine session, muted locally and without
autoplay. It refuses sources outside a bounded H.264/HEVC, original-compatible
single-audio-track fixture set. It requires native loopback delivery and reports
the public AVPlayer item's URL. Native WebVTT renditions are enabled. Software
escalation, optional object rendering and optional FEL processing are not enabled.

`compare.py` snapshots the engine's complete HLS output over local HTTP. The
snapshot refuses unfinished VOD, redirects, cross-origin references and excess
resources/bytes. It never passes a growing playlist to a receiver. The host is
stopped and its process joined on success and failure.

`Baseline.swift` invokes the actual AirCiller HLSPreparationService with original
audio, embedded subtitles, no cache and zero timing adjustments. It is not a
handwritten FFmpeg approximation. No production source is copied or modified.

The comparison requires identical decoded video frames, identical ordered audio
packet hashes, expected WebVTT text and an unchanged source. A mismatch returns
failure; the test is not relaxed to accept an engine's different policy.
Packet timestamps, skip metadata and decoded PCM counts/initial RMS are retained
for diagnosis; they do not replace the packet-preservation gate.

Reports and manifests stay under a storage-guarded `.build/performance/run.*`.
Generated movies, segments and executables inside those runs are removed after
completion. Engine tools stay in their dependency directory. The local URL/token
and diagnostic logs are private evidence and must not be published.

## Current result

Latest opt-in result: AAC now passes exact packet and decoded-sample equality.
E-AC-3 does not: a native macOS reader also produces a different sample count.
No receiver comparison has been started. The sections below retain the earlier
pre-roll-stage failure; see the review for the newest exact-edit evidence.

The optional `AIRCILLER_TAIL_DURATION_PROBE=1` now corrects the final E-AC-3
block duration without changing media bytes or fragment start times. It has not
resolved the native discrepancy. The native comparison also constructs a
stream-copy MP4 reference: Apple produces identical bytes for it and Aether,
but that reference fails source PCM fidelity, so neither result is accepted.
Diagnostics retain first/last packets, native buffer trims and sample hashes.
No automatic acceptance or Apple TV execution is enabled by these flags.

`AIRCILLER_EXACT_EDIT_PROBE=1` enables `trim_metadata.py` after the snapshot is
complete. It preserves packets and fragment timestamps and corrects only the
audio edit-list pre-roll and duration. Source decoding supplies the research
duration; nothing is encoded, and this is not a proposed production startup path.
Run `python3 -B Prototypes/AetherComparison/test_trim_metadata.py` for its tests.

Optional `AIRCILLER_NATIVE_READ_PROBE=1` additionally reads a concatenation of the
same finalized fragments with macOS AVAssetReader. Build its helper with:

```sh
xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors Prototypes/AetherComparison/ReadAudio.swift -o .build/aether-read-audio
```

The helper requires the current macOS 27 API. It reads files only, without
playback/capture. Native counts are separate evidence, not a replacement for a
failed comparison. E-AC-3 still fails; do not connect this candidate to the TV.

### Opt-in pre-roll experiment (not accepted)

`preroll-experiment.patch` applies only to the pinned, ignored Aether checkout.
It is not applied by `build.sh` and must not ship. Apply it once from the project
root with `git -C .build/dependencies/AetherEngine-7.62.0 apply ../../../Prototypes/AetherComparison/preroll-experiment.patch`,
then rebuild the host. Run each comparison with `AIRCILLER_PREROLL_PROBE=1`
scoped to that command, selecting `aac` or `eac3` as its final argument.
An already-applied patch is not a reason to overwrite the checkout.

The experiment reopens a local fixture at its actual beginning, preserves
pre-zero packets and enables MP4 presentation edit lists. Arbitrary nonzero
starts, restarts, live sources and remote input are not validated. Do not use it
on the TV. Both fixtures now retain every packet, but decoded audio still fails
parity: AAC has 16 extra samples and E-AC-3 has 384 extra samples relative to
the source decoder's presentation output. Source skip/discard metadata still
needs correct mapping. Exact PCM equality is now required alongside packet
equality. Host diagnostics remain in ignored local reports.

See [the review](../../Docs/AETHER_PROTOTYPE_2026_11.md). The first valid comparison
preserves every video frame and the subtitle, but Aether omits the first AAC
packet. Follow-up identifies AAC priming with a decoded initial difference and
an E-AC-3 straddling packet containing useful audio that is also omitted.
This is not equivalent original-audio handling. The prototype has
not been connected to the Apple TV, and it does not demonstrate AirPlay 2,
HDR/DV receiver output, long pauses, remote controls or whole-film reliability.

The intended next stage is a separate, authorized adapter to AirCiller's existing
AirPlay 2 controller and exact approved digital capture source. Aether's media
engine is not a replacement for discovery, pairing or remote control. Do not use
the installed app or alter its credentials to shortcut that comparison.

# AirCiller

[Leer en español](README.es.md)

AirCiller is a lightweight macOS app for opening a local video file and sending it to an Apple TV over AirPlay 2. It is designed around a simple **open, send, watch** workflow, with no permanent library, cloud service, telemetry, or silent transcoding.

> Status: personal project under active development. Version 0.9.8 is currently installed and has been validated on a physical Apple TV. The development branch may contain changes that still require real-device testing.

## Features

- Preserves the original H.264/HEVC video, including HDR and Dolby Vision when supported by the file and tvOS.
- Keeps two playback paths independent: direct MP4 for HDR/Dolby Vision and HLS/fMP4 VOD for other cases.
- Lets you select audio tracks, adjust audio timing, and convert audio only after an explicit choice.
- Provides selectable SRT, WebVTT, ASS/SSA, Blu-ray PGS, and DVD VobSub subtitles through local Apple Vision OCR.
- Keeps a local playlist, playback progress, chapters, and synchronized Apple TV controls.
- Analyzes media demand and network capacity on request, without telemetry or permanent background processes.

AirCiller does not download or include media. Use it only with files you have the right to play.

## Project principles

- Never modify the original file.
- Never transcode video or audio without explaining why and asking first.
- Never burn subtitles into the picture or upload them to an external service.
- Keep the direct MP4 and HLS/fMP4 paths separate and independently tested.
- Never claim Apple TV validation based only on a local test.

## Requirements

- Apple Silicon Mac running macOS 14 or later.
- Xcode Command Line Tools with Swift 6.
- [FFmpeg](https://ffmpeg.org/) and `ffprobe`, available through Homebrew or MacPorts. The current validated reference is FFmpeg 9.0.1.
- Python 3.11 or later to prepare the local AirPlay engine.
- An AirPlay 2-compatible Apple TV on the same local network.

## Setup and build

```sh
brew bundle
./Scripts/bootstrap_dependencies.sh
./build.sh
```

The build is written to `.build/AirCiller.app`. Building does not replace or launch any installed copy. Rebuild `VendorPython` on each Mac and whenever the Python version changes to avoid binary incompatibilities.

## Checks

```sh
./Scripts/check.sh
```

Automated checks cover application logic, the HTTP server, subtitles, and a simulated AirPlay bridge without contacting an Apple TV. Tests that require real media receive file paths through arguments or environment variables; those files are never part of the repository.

Before installing a release, validate these cases separately on a physical Apple TV:

1. Direct HDR/Dolby Vision MP4 with E-AC-3/Atmos and selectable subtitles.
2. HLS/fMP4 VOD with WebVTT, both with and without subtitles.
3. Long pause and resume, position updates, stop, and remote control.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the design, [TESTING.md](TESTING.md) for validation, [ROADMAP.md](ROADMAP.md) for planned work, and [CHANGELOG.md](CHANGELOG.md) for release history.

## Privacy and security

All processing happens on the Mac. During playback, AirCiller opens a temporary HTTP server restricted to the local network and protected by a random session path. It has no accounts, analytics, cloud service, or automatic updater. AirPlay credentials are stored in the macOS Keychain.

Do not open public issues containing device names, local addresses, or private filenames. Read [SECURITY.md](SECURITY.md) before sharing diagnostics.

## Origin and attribution

AirCiller is an independent project developed, reviewed, and debugged with substantial assistance from **OpenAI Codex**. Product decisions and physical validation remain the maintainer's responsibility. OpenAI does not sponsor or endorse this project.

AirCiller is not affiliated with Apple. Apple, macOS, tvOS, Apple TV, and AirPlay are trademarks of Apple Inc. The AirCiller name and icon are original parts of the project's own identity.

## License

AirCiller source code and original artwork are released under the [GNU General Public License v3.0](LICENSE). If you distribute a modified version, you must make its corresponding source available under the same license. Dependencies retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

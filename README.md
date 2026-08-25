<div align="center">
  <img src="Resources/AirCiller-1024.png" width="132" alt="AirCiller app icon">
  <h1>AirCiller</h1>
  <p><strong>Your movie. Your Apple TV. Nothing in between.</strong></p>
  <p>A small, native macOS app for sending local video to Apple TV over AirPlay 2 — with HDR, Dolby Vision, audio tracks, and selectable subtitles when the source allows it.</p>
  <p>
    <a href="https://github.com/carlosciller/AirCiller/releases/latest"><strong>Download AirCiller</strong></a>
    · <a href="README.es.md">Español</a>
    · <a href="CHANGELOG.md">What’s new</a>
  </p>
  <p>
    <a href="https://github.com/carlosciller/AirCiller/releases/latest"><img src="https://img.shields.io/github/v/release/carlosciller/AirCiller?style=flat-square&label=release" alt="Latest release"></a>
    <a href="https://github.com/carlosciller/AirCiller/actions/workflows/ci.yml"><img src="https://github.com/carlosciller/AirCiller/actions/workflows/ci.yml/badge.svg" alt="Build status"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/carlosciller/AirCiller?style=flat-square" alt="GPL-3.0 license"></a>
  </p>
</div>

AirCiller began with a simple frustration: a great movie file on a Mac should not require a media-library project, an account, or a mystery conversion before it reaches the television.

Open a file, choose the Apple TV, pick the tracks, and press Play. AirCiller does the careful work and then gets out of the way.

## Made for watching, not managing

- **Keep the picture you chose.** H.264 and HEVC video can stay untouched, including HDR and Dolby Vision on compatible files and Apple TV models.
- **Use the tracks already inside the movie.** Choose audio and subtitles before playback, change compatible tracks later, and adjust timing when a release needs it.
- **Make bitmap subtitles useful.** SRT, WebVTT, and ASS/SSA work alongside Blu-ray PGS and DVD VobSub, which AirCiller can turn into selectable text locally with Apple Vision OCR.
- **Stay in sync with the television.** Pause, resume, seek, and playback position follow the Apple TV remote instead of pretending the Mac is still in control.
- **Keep a small, practical library.** Playlist ordering, recent movies, progress, and chapters are available without asking you to build a permanent media server.
- **See diagnostics only when they help.** Network demand, available margin, and preparation details live behind an information panel rather than filling the player with numbers.

## Download

The current stable release is **AirCiller 0.10.1** for Apple silicon Macs running macOS 14 or later.

### [Download the latest release →](https://github.com/carlosciller/AirCiller/releases/latest)

Unzip AirCiller and move it to your Applications folder. The current public build is locally signed rather than notarized with an Apple Developer ID, so macOS may ask you to confirm its first launch. If you would rather inspect every step, build it from source below.

You will also need:

- An AirPlay 2-compatible Apple TV on the same local network.
- [FFmpeg](https://ffmpeg.org/) and `ffprobe`; Homebrew and MacPorts are supported.

## Private by design

AirCiller has no account, advertising, telemetry, analytics, cloud library, or permanent server.

- Movies and originals are never uploaded or modified.
- Video is never silently transcoded.
- Audio conversion is explained before it happens and requires an explicit choice.
- Bitmap subtitle OCR runs on the Mac and produces a selectable local track; subtitles are never burned into the picture.
- The temporary playback server exists only on the local network and closes with the session.
- AirPlay credentials live in the macOS Keychain.

The complete behavior is documented in [PRIVACY.md](PRIVACY.md).

## How playback stays faithful

AirCiller keeps two playback routes separate:

1. **Direct MP4** preserves compatible HDR/Dolby Vision video and supported audio without video transcoding.
2. **HLS/fMP4 VOD** packages other compatible sources for Apple TV and can add selectable WebVTT subtitles.

The app tells you which route it is using and why. If a track is not accepted by Apple TV, AirCiller explains the incompatibility instead of silently changing it.

## Under the hood

AirCiller is a native Swift 6 application built with SwiftUI and AppKit. The GitHub language bar also shows a small amount of Python: that is the bundled `pyatv` bridge responsible for AirPlay 2 discovery, authorization, queue control, and receiver events. It is not the interface or the media pipeline.

FFmpeg inspects and packages media when needed; Apple Vision performs local subtitle OCR. During playback, a temporary private HTTP server lets the Apple TV read the selected file or prepared VOD. Internet access is not required for playback.

For the deeper version, see [Architecture](ARCHITECTURE.md) and [Testing](TESTING.md).

## Build from source

Requirements:

- Apple silicon Mac with macOS 14 or later.
- Xcode Command Line Tools with Swift 6.
- FFmpeg and `ffprobe`. The current validated reference is FFmpeg 9.0.1.
- Python 3.11 or later for the reproducible AirPlay bridge environment.

```sh
brew bundle
./Scripts/bootstrap_dependencies.sh
./build.sh
```

The app is created at `.build/AirCiller.app`; building never replaces or launches an installed copy.

Run the complete local validation with:

```sh
./Scripts/check.sh
```

Playback changes are tested locally and then separately on a physical Apple TV through both routes before they become an installed release. Read [CONTRIBUTING.md](CONTRIBUTING.md) before proposing a change.

## A personal project, made in the open

AirCiller is intentionally small and opinionated. It was built for one living room, then carefully generalized so somebody else could understand it, audit it, and perhaps find it useful.

It is maintained by [Carlos Ciller](https://github.com/carlosciller) and has been developed, reviewed, and debugged with substantial assistance from **OpenAI Codex**. That collaboration is part of the project’s history, not a substitute for human judgment: product decisions and physical Apple TV validation remain the maintainer’s responsibility. OpenAI does not sponsor or endorse the project.

Bug reports and focused ideas are welcome. Please remove private filenames, receiver names, addresses, and credentials before opening an issue.

## License and trademarks

AirCiller’s source code and original artwork are free software under the [GNU General Public License v3.0](LICENSE). Dependencies keep their own licenses; see [Third-party notices](THIRD_PARTY_NOTICES.md).

AirCiller is independent and is not affiliated with Apple. Apple, macOS, tvOS, Apple TV, and AirPlay are trademarks of Apple Inc. The AirCiller name and icon are original parts of this project.

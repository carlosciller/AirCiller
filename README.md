<div align="center">
  <img src="Resources/AirCiller-1024.png" width="132" alt="AirCiller app icon">
  <h1>AirCiller</h1>
  <p><strong>Play local movies on Apple TV from your Mac.</strong></p>
  <p>AirCiller is a native macOS app with support for HDR, Dolby Vision, multiple audio tracks and selectable subtitles.</p>
  <p>
    <a href="https://github.com/carlosciller/AirCiller/releases/latest"><strong>Download AirCiller</strong></a>
    · <a href="CHANGELOG.md">Release notes</a>
  </p>
  <p>
    <a href="https://github.com/carlosciller/AirCiller/releases/latest"><img src="https://img.shields.io/github/v/release/carlosciller/AirCiller?style=flat-square&label=release" alt="Latest release"></a>
    <a href="https://github.com/carlosciller/AirCiller/actions/workflows/ci.yml"><img src="https://github.com/carlosciller/AirCiller/actions/workflows/ci.yml/badge.svg" alt="Build status"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/carlosciller/AirCiller?style=flat-square" alt="GPL-3.0 license"></a>
  </p>
</div>

AirCiller is available in English and Spanish.

## What it does

- Sends local H.264 and HEVC video to an AirPlay 2 compatible Apple TV.
- Preserves compatible HDR and Dolby Vision video.
- Lets you choose audio and subtitle tracks and adjust their timing.
- Supports SRT, WebVTT and ASS/SSA subtitles.
- Uses local Apple Vision OCR to make Blu-ray PGS and DVD VobSub subtitles selectable.
- Keeps playback position, pause, resume and seeking synchronized with the Apple TV remote.
- Includes an ordered playlist, recent movies, chapters and saved progress.
- Provides optional network and preparation diagnostics.
- Checks for signed updates through Sparkle when a release feed is configured.

AirCiller does not download or include media. Use it with files you have the right to play.

## Download

The current stable release is **AirCiller 0.10.4**. It requires an Apple silicon Mac running macOS 14 or later.

### [Download the latest release](https://github.com/carlosciller/AirCiller/releases/latest)

Unzip AirCiller and move it to your Applications folder. The current build is locally signed and has not yet been notarized with an Apple Developer ID. macOS may ask you to confirm the first launch.

You will also need an AirPlay 2 compatible Apple TV on the same local network.

AirCiller can download verified FFmpeg and AirPlay components from its Components settings. Existing Homebrew or MacPorts installations remain supported as a manual alternative.

## Privacy

Movies remain on the Mac and original files are never modified. AirCiller has no accounts, advertising, analytics, cloud library or permanent server.

Video conversion never happens silently. If an audio track needs conversion, AirCiller explains why and asks first. Subtitle OCR runs locally and creates a selectable text track. It does not burn subtitles into the image.

The temporary playback server is available only on the local network and closes when the session ends. AirPlay credentials are stored in the macOS Keychain. See [PRIVACY.md](PRIVACY.md) for the full details.

## Playback

AirCiller uses two playback routes:

1. **Direct MP4** for compatible HDR or Dolby Vision video and supported audio.
2. **HLS/fMP4 VOD** for other compatible sources and selectable WebVTT subtitles.

The app shows which route is being used. It also explains when Apple TV cannot accept a selected track.

## Technical details

Most of AirCiller is written in Swift 6 with SwiftUI and AppKit. The repository also contains a small Python component: a bundled `pyatv` bridge used for AirPlay 2 discovery, authorization, queue control and receiver events.

FFmpeg inspects and packages media when required. Apple Vision handles subtitle OCR on the Mac. A temporary HTTP server supplies the selected file or prepared VOD to Apple TV during playback. Once the required components are installed, playback stays on the local network and does not require internet access.

See [ARCHITECTURE.md](ARCHITECTURE.md), [TESTING.md](TESTING.md) and [DISTRIBUTION.md](DISTRIBUTION.md) for more detail.

## Build from source

Requirements:

- Apple silicon Mac with macOS 14 or later.
- Xcode Command Line Tools with Swift 6.
- FFmpeg and `ffprobe`. The current validated reference is FFmpeg 9.0.1.
- Python 3.13 for the AirPlay bridge environment.

```sh
brew bundle
./Scripts/bootstrap_dependencies.sh
./Scripts/bootstrap_sparkle.sh
./build.sh
```

The app is created at `.build/AirCiller.app`. Building does not replace or launch an installed copy.

Run the local checks with:

```sh
./Scripts/check.sh
```

Playback changes are tested locally and on a physical Apple TV before release. Read [CONTRIBUTING.md](CONTRIBUTING.md) before proposing a change.

## About the project

I started AirCiller because I wanted a quick way to play the movie files on my Mac through Apple TV, including the awkward ones with Dolby Vision or unusual subtitles. It grew through a lot of testing on my own Mac and Apple TV. I published the source because other people may find it useful and because I did not want all that work to live on one Mac.

I use **OpenAI Codex** to help me write, review and debug the code. I decide how the app should work and test each release on the actual hardware. OpenAI does not sponsor or endorse AirCiller.

Bug reports and focused ideas are welcome. Please remove private filenames, receiver names, addresses and credentials before opening an issue.

## License and trademarks

AirCiller's source code and original artwork are licensed under the [GNU General Public License v3.0](LICENSE). Dependencies retain their own licenses; see [Third-party notices](THIRD_PARTY_NOTICES.md).

AirCiller is independent and is not affiliated with Apple. Apple, macOS, tvOS, Apple TV and AirPlay are trademarks of Apple Inc. The AirCiller name and icon are original parts of this project.

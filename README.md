<div align="center">
  <img src="Resources/AirCiller-1024.png" width="128" alt="AirCiller">
  <h1>AirCiller</h1>
  <p>Play the movies on your Mac on your Apple TV.</p>
  <p><a href="https://github.com/carlosciller/AirCiller/releases/latest"><strong>Download AirCiller</strong></a> · <a href="CHANGELOG.md">What's new</a> · <a href="https://github.com/carlosciller/AirCiller/issues">Report a bug</a></p>
</div>

Open a movie, choose your Apple TV and press Play. AirCiller sends it over AirPlay 2, with audio and subtitle tracks you can change along the way.

Free and open source. Available in English and Spanish.

## Get started

You need an **Apple silicon Mac with macOS 14 or later**, an AirPlay 2 compatible Apple TV, and a local network that lets the two devices communicate. HDR and Dolby Vision also need compatible television and receiver hardware.

1. [Download AirCiller](https://github.com/carlosciller/AirCiller/releases/latest), unzip it and move it to Applications.
2. Open a movie and choose your Apple TV. Enter the code shown on the television if requested.
3. Press Play. Use AirCiller, the Apple TV remote or the iPhone Remote to pause, seek and resume.

**First launch:** AirCiller is not notarized with Apple. macOS may block a downloaded copy until you allow it in Privacy & Security. Follow [Apple's instructions](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac), and only open a copy you trust.

The playback engines are included. There is nothing else to install. Future updates arrive through the app with your confirmation.

## Your tracks, your playlist

- **Original picture.** Compatible H.264 and HEVC video, including HDR and Dolby Vision, is sent without video encoding.
- **Original audio first.** Choose a track by name and language. If audio needs conversion, AirCiller explains the change and asks before starting.
- **Selectable subtitles.** Embedded and external text tracks, timing adjustments, and local text recognition for embedded Blu-ray PGS and DVD VobSub subtitles.
- **Language preferences.** Set preferred audio and subtitle languages, including standard, forced or SDH subtitles.
- **A small library.** Reorder your Playlist, browse recent movies and pick up where you left off. Chapters and keyboard controls are included.
- **Optional subtitle search.** Search OpenSubtitles.com, review the matches and choose a download. Your own API key is required; service limits apply.

Not every file will play. Elaborate ASS styling is simplified, OCR can make mistakes, and unsupported audio may need conversion. [Read the compatibility guide](COMPATIBILITY.md).

## On your Mac

AirCiller has no advertising or analytics. Movies stay on the local network, originals are never changed, and the playback server closes when the session ends. Subtitle recognition runs on the Mac.

Internet access is used for updates and OpenSubtitles searches you request. OpenSubtitles receives search information, never the movie. Credentials stay in the macOS Keychain. [Privacy details](PRIVACY.md).

## About

I started AirCiller to watch my own movie collection on Apple TV. Dolby Vision, subtitles and remote controls took quite a few evenings to get right. I shared the project so others could use it, inspect it and help improve it.

I use **OpenAI Codex** to write, review and debug the code. I make the product decisions and test playback on my Mac and Apple TV. OpenAI does not sponsor or endorse the project.

Found a problem? [Open an issue](https://github.com/carlosciller/AirCiller/issues) with the app version, file format and what happened. Please remove personal filenames, device names, addresses and credentials. The [roadmap](ROADMAP.md) shows what is being worked on.

## Build and contribute

The app uses Swift 6, SwiftUI and AppKit. A bundled Python bridge provides AirPlay 2 through pyatv. FFmpeg prepares compatible media and Apple Vision recognizes bitmap subtitles.

On an Apple silicon Mac with the Swift 6 Command Line Tools:

```sh
brew bundle
./Scripts/bootstrap_dependencies.sh
./Scripts/bootstrap_sparkle.sh
./Scripts/bootstrap_engine.sh
./Scripts/check.sh
```

The checks build `.build/AirCiller.app` without replacing or launching an installed copy. Use `./build.sh` for subsequent development builds.

[Contributing](CONTRIBUTING.md) · [Architecture](ARCHITECTURE.md) · [Testing](TESTING.md) · [Distribution](DISTRIBUTION.md)

## License

AirCiller's source and original artwork are licensed under [GPL-3.0](LICENSE). Dependencies keep their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md).

AirCiller is an independent project. Apple, macOS, tvOS, Apple TV and AirPlay are trademarks of Apple Inc.

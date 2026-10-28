<div align="center">
  <img src="Resources/AirCiller-1024.png" width="128" alt="AirCiller">
  <h1>AirCiller</h1>
  <p>Watch your movie collection on Apple TV, from your Mac.</p>
  <p><a href="https://github.com/carlosciller/AirCiller/releases/latest"><strong>Download AirCiller</strong></a> · <a href="CHANGELOG.md">What's new</a> · <a href="COMPATIBILITY.md">Compatibility</a> · <a href="https://github.com/carlosciller/AirCiller/issues/new/choose">Get help</a></p>
</div>

Open a movie, choose your Apple TV and press Play. AirCiller sends it over AirPlay 2, with audio and subtitle tracks you can change along the way.

Free and open source. **Apple silicon · macOS 14 or later · English and Spanish.**

## Get started

You need an **Apple silicon Mac with macOS 14 or later**, an AirPlay 2 compatible Apple TV, and a local network that lets the two devices communicate. HDR and Dolby Vision also need compatible television and receiver hardware.

1. [Download the AirCiller ZIP](https://github.com/carlosciller/AirCiller/releases/latest), unzip it and move the app to Applications. Choose the AirCiller ZIP under **Assets**, not GitHub's source-code archive.
2. Open a movie and choose your Apple TV. Enter the code shown on the television if requested.
3. Press Play. Use AirCiller, the Apple TV remote or the iPhone Remote to pause, seek and resume.

**First launch:** AirCiller is not notarized with Apple. macOS may block a downloaded copy until you allow it in Privacy & Security. Follow [Apple's instructions](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac), and only open a copy you trust.

The playback engines are included. There is nothing else to install. Future updates arrive through the app with your confirmation.

## Movies, seasons and tracks

- **Original picture.** Compatible H.264 and HEVC video, including HDR and Dolby Vision, is sent without video encoding.
- **Original audio first.** Choose a track by name and language. If audio needs conversion, AirCiller explains the change and asks before starting.
- **Selectable subtitles.** Embedded and external text tracks, timing adjustments, and local text recognition for Blu-ray PGS and DVD VobSub subtitles, including `.sup` and `.idx`/`.sub` files.
- **Language preferences.** Set preferred audio and subtitle languages, including standard, forced or SDH subtitles.
- **Season folders.** Drop a folder into Playlist to add a season. Expand it to choose an episode, mark episodes watched or unwatched, and continue with the next one. Order and progress are saved between launches.
- **Playlist and Recents.** Add movies individually or together, reorder them by dragging or keyboard, and undo library edits. Adding files leaves an existing playback session alone.
- **Optional subtitle search.** Search OpenSubtitles.com, review the matches and choose a download. Your own API key is required; service limits apply.

## Will my files play?

AirCiller opens MKV, MP4, M4V, MOV, TS, MTS and M2TS files. The video and audio
inside still need to be supported. Compatible tracks are preserved; changing
the container does not mean re-encoding the picture.

Unsupported audio may need an explicitly approved conversion. Video conversion
is not available. Dolby Vision support depends on the profile and playback
hardware. Elaborate ASS styling is simplified, and subtitle OCR can make mistakes.

The [compatibility guide](COMPATIBILITY.md) lists supported tracks and known
limits. See [season folders](Docs/LIBRARY_SEASONS.md) for import and ordering
details. Removing an item from Playlist never deletes its original file.


## On your Mac

AirCiller has no advertising or analytics. Movies stay on the local network, originals are never changed, and the playback server closes when the session ends. Subtitle recognition runs on the Mac.

Internet access is used for updates and OpenSubtitles searches you request.
AirPlay and subtitle-service credentials stay in the macOS Keychain.
[Privacy details](PRIVACY.md).

An optional [private ChatGPT connector](Docs/PRIVATE_REMOTE_CONTROL.md) can
control playback and open or close the app while the Mac is awake, even with
its screen locked. It requires your own relay and credentials; no hosted
service is included. Commands and necessary titles, tracks, progress and errors
pass through that connection, never movies or subtitle contents. It cannot wake
or unlock the Mac.

## About

I started AirCiller to watch my own movie collection on Apple TV. Dolby Vision, subtitles and remote controls took quite a few evenings to get right. I shared the project so others could use it, inspect it and help improve it.

I use **OpenAI Codex** to write, review and debug the code. I make the product decisions and test playback on my Mac and Apple TV. OpenAI does not sponsor or endorse the project.

## Help and plans

Found a problem? [Report it](https://github.com/carlosciller/AirCiller/issues/new/choose)
with the app version, file format and what happened. Please remove personal
filenames, device names, addresses and credentials. Report security problems
[privately](SECURITY.md).

The [roadmap](ROADMAP.md) explains the next priorities, what is already available
and what needs more evidence. It is not a release schedule.

## Build and contribute

The app uses Swift 6, SwiftUI and AppKit. A bundled Python bridge provides AirPlay 2 through pyatv. FFmpeg prepares compatible media and Apple Vision recognizes bitmap subtitles.

Development requires an Apple silicon Mac and the Swift 6 Command Line Tools.
Follow [checkout preparation and checks](CONTRIBUTING.md#prepare-a-checkout).
The checks build `.build/AirCiller.app` without replacing or launching an installed
copy. Use `./build.sh` for subsequent development builds.

[Contributing](CONTRIBUTING.md) · [Architecture](ARCHITECTURE.md) · [Testing](TESTING.md) · [Distribution](DISTRIBUTION.md)

## License

AirCiller's source and original artwork are licensed under [GPL-3.0](LICENSE). Dependencies keep their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md).

AirCiller is an independent project. Apple, macOS, tvOS, Apple TV and AirPlay are trademarks of Apple Inc.

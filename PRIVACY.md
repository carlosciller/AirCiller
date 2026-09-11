# Privacy

AirCiller has no AirCiller account, telemetry, analytics, advertising, or cloud library. It can check GitHub for signed app updates and can use OpenSubtitles.com when you explicitly ask it to find a subtitle.

## Data processed on the Mac

- The playlist, recent items, playback position, and file paths are stored in the app's local preferences.
- AirPlay credentials are stored in the macOS Keychain.
- PGS subtitle OCR runs through Apple Vision. Its WebVTT result may remain in a local cache to avoid repeating recognition.
- OpenSubtitles API and account credentials are stored in the macOS Keychain. Downloaded subtitles remain in the local subtitle cache until you clear it.
- Session-specific VOD playlists and tracks are created in temporary storage and removed when the session ends or during later cleanup.
- Finalized HLS video and audio can remain in the local prepared-media cache for reuse. Settings > Storage shows its size and provides a limit, Off and Clear controls. The default retention limit is 16 GiB. Direct HDR MP4 preparations are not retained by this cache. Cache removal never removes original movies.

## Internet services

- Update checks request signed release metadata from GitHub. AirCiller asks before installing an update.
- OpenSubtitles searches happen only after you choose **Find on OpenSubtitles**. The first request contains the movie file fingerprint, file size, and requested language. If there is no exact match, AirCiller sends the search text shown in the search field. The movie itself is never uploaded.
- If you configure an OpenSubtitles account, AirCiller sends its username and password directly to OpenSubtitles over HTTPS to obtain a temporary login token. The token stays in memory and is discarded when the app closes.
- AirCiller downloads only the subtitle you select. OpenSubtitles applies its own account and download limits.

## Local network

During playback, AirCiller opens a temporary HTTP server on the local network so the Apple TV can read the file or VOD. The URL contains a random session path, and the server closes when playback stops. AirPlay requires this local transport without TLS; it is not exposed to the Internet and does not act as a permanent server.

## Logs

The macOS unified log may contain technical state, but filenames, receivers, addresses, and URIs are marked private. Before sharing diagnostics, review and remove any remaining personal data.

An exported local diagnostic can include HLS preparation stage timings and cache-hit status. These measurements contain no movie path/title, receiver identity or credentials. They are only exported when requested and are not transmitted automatically.

AirCiller does not send your library, diagnostics, or credentials to its maintainer or OpenAI. Data sent to GitHub and OpenSubtitles is limited to the actions described above.

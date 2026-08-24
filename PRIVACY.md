# Privacy

AirCiller has no accounts, telemetry, analytics, advertising, cloud service, or automatic updater.

## Data processed on the Mac

- The playlist, recent items, playback position, and file paths are stored in the app's local preferences.
- AirPlay credentials are stored in the macOS Keychain.
- PGS subtitle OCR runs through Apple Vision. Its WebVTT result may remain in a local cache to avoid repeating recognition.
- Prepared VODs and tracks are created in temporary storage and removed when the session ends or during later cleanup.

## Local network

During playback, AirCiller opens a temporary HTTP server on the local network so the Apple TV can read the file or VOD. The URL contains a random session path, and the server closes when playback stops. AirPlay requires this local transport without TLS; it is not exposed to the Internet and does not act as a permanent server.

## Logs

The macOS unified log may contain technical state, but filenames, receivers, addresses, and URIs are marked private. Before sharing diagnostics, review and remove any remaining personal data.

AirCiller does not send your library, subtitles, diagnostics, or credentials to its maintainer, OpenAI, or any third party.

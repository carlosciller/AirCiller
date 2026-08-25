# AirCiller changelog

Installed versions are validated separately on macOS and on a physical Apple TV. Changes that have not completed that validation are documented under `Unreleased`.

## Unreleased

- Updates FFmpeg to Homebrew revision 9.0.1_1 and Python to 3.13.15, then aligns the Brewfile, dependency bootstrap and runtime fallback with Python 3.13.
- Identifies Now Playing content explicitly as a finite movie, publishes playlist position and progress, and keeps local filenames out of system content suggestions.
- Adds native Playback, Components and Storage settings, including preferred audio and subtitle languages with safe file-track fallbacks.
- Shows the installed FFmpeg and AirPlay engine versions, source and path, with explicit Homebrew install or update actions, an activity indicator and cancellation. Component changes stay disabled during playback.
- Keeps automatic app updates disabled while releases are ad hoc signed; no component or app update runs silently.
- Records the current Developer ID and notarization blockers, adds a repeatable distribution audit, and defines signed hosting for future updates and managed components.
- Corrects the public requirements to include Python until AirCiller provides its own managed runtime.
- Removes formulaic wording from the remaining public project text.
- Rewrites the public README in a more direct, personal voice and removes the separate Spanish README. The app remains available in English and Spanish.
- Redesigns the public GitHub landing page around download, real-world use, privacy and the project's origin, with technical details later in the document.
- Adds privacy-aware bug and feature forms, enables private vulnerability reporting, and documents the future signed Sparkle updater without changing the app itself.
- Removes the local receiver-name preference from discovery so public builds select Apple TV devices without relying on a developer-specific room name.
- Extends the publication audit to reject local receiver names and legacy third-party product references.

## Version 0.10.1

- Cancels FFmpeg, ffprobe, text-subtitle extraction, and bitmap OCR with the task that owns them, including progress-reporting preparation jobs.
- Adds selectable DVD VobSub through the existing on-demand FFmpeg and local Apple Vision OCR pipeline; no subtitle is burned in and originals remain untouched.
- Adds native macOS Storage settings with a visible 128 MB–2 GB OCR cache limit, clear controls, LRU pruning, and safe removal of abandoned preparation files.
- Chooses the Mac's serving address from the effective route to the selected Apple TV, with the existing interface scan retained as a fallback for VPN and multi-interface setups.
- Adds deterministic Swift 6 tests for process cancellation, cache limits, temporary-file cleanup, route selection, and VobSub metadata.
- Validates VobSub locally as positioned HLS/WebVTT and as a selectable track in a copied Dolby Vision MP4, then physically validates selectable OCR subtitles, picture, and audio on Apple TV 4K with tvOS 27.0.
- Corrects the tightly scoped `& … s` Apple Vision misreading around song lyrics back to `♪ … ♪`, including multiline cues, without replacing normal ampersands or plural words; VobSub OCR cache revision 2 regenerates affected tracks once.

## Version 0.9.8

- Requires a real media request from Apple TV before declaring playback started, closing false or ghost sessions cleanly.
- Treats a failed AirPlay 2 `/feedback` path as non-terminal while the independent event channel and media transfer remain healthy.
- Preserves instant pause, resume, and timeline updates from the Apple TV remote instead of tearing down an active stream.
- Adds regression coverage for consecutive and intermittent feedback failures and understandable lost-control errors.
- Physically validated on Apple TV 4K with tvOS 27.0: direct Dolby Vision with selectable subtitles; HLS/fMP4 with SRT/WebVTT, PGS, and no subtitles; converted FLAC audio; remote pause and resume.
- Adds native English and Spanish localization that follows the language selected for AirCiller in macOS.
- Publishes the primary README, project documentation, templates, and developer-facing checks in English while retaining a complete Spanish README.
- Prepares the public repository with a reproducible build, documentation, automated checks, and no personal paths in manual tests.
- Keeps the installed app unchanged until AirPlay 2 passes physical validation again.
- Moves the auxiliary AirPlay environment from Python 3.9 to Python 3.13 and locks dependencies with hashes; pyatv remains on the latest stable release, 0.18.0.
- Updates aiohttp, requests, urllib3, and zeroconf to patched versions and preserves dependency license notices inside the bundle.
- Pins the Apple TV used by each session so a later discovery or selection cannot invalidate credentials for the wrong receiver.
- Separates manual authorization from authorization requested during playback: renewing from the menu no longer starts a movie by itself.
- Waits for Apple TV confirmation before reflecting pause or resume and reports an error if the control channel no longer exists.
- Marks filenames, receivers, addresses, and URIs as private in logs.
- Makes `build.sh` generate only `.build/AirCiller.app`; installation is a separate explicit action that creates a rollback copy.

## Version 0.9.7

- Replaces the experimental SwiftUI reorder implementation with the mature native AppKit table used by classic macOS lists.
- The entire card and its handle start dragging; the system draws an insertion line between rows, supports the true end of the list, and scrolls automatically at the edges.
- The list no longer mutates or recalculates row heights while dragging: AirCiller saves the new order once, on drop, eliminating upward jitter.
- Uses the same implementation from macOS 14 onward, without separate behaviors by system version.
- Adds `Move to Top` and `Move to Bottom` to the context menu as an accessible alternative to dragging.
- Adds no dependencies and leaves both AirPlay 2 playback paths untouched.
- Builds with strict Swift 6 and warnings-as-errors; model and AirPlay 2 engine tests pass. Final human gesture validation was still pending when this entry was written.

## Version 0.9.6

- Prevents only automatic Mac sleep while AirCiller prepares, plays, or keeps a movie paused; the display still follows the user's settings.
- Keeps the assertion active through long pauses so macOS does not suspend the local server or AirPlay 2 control channel.
- Releases it immediately on stop, completion, or failure; AirCiller does not keep the Mac awake after the session ends.
- Adds an isolated lifecycle test, including idempotent acquisition and release.
- Physically validated on Apple TV 4K with tvOS 27.0: pause longer than two minutes, preserved link, confirmed resume, later progress without `not connected`, and assertion removed on stop.

## Version 0.9.5

- Reuses HTTP/1.1 connections between Apple TV and the local server, avoiding thousands of unnecessary TCP openings during player read bursts.
- Serves prepared files with private immutable caching while preserving the byte-range requests AVPlayer requires.
- Fixes the case where tvOS sends a complete request and closes its write side in the same operation; AirCiller no longer mistakes it for an incomplete request or returns a spurious HTTP 400.
- Separates local tests and other clients from stream measurement so throughput diagnostics reflect only traffic to the selected Apple TV.
- Adds tests for multiple ranges on one persistent connection, unilateral close after a complete request, files larger than 4 GB, caching, and telemetry filtering.
- Physically validated on Apple TV 4K with tvOS 27.0: Dolby Vision, E-AC-3, and selectable subtitles; 3:36 from the beginning, 2,954 requests, 273 reused connections, 0 HTTP 400 responses, and 0 stalls. Version 0.9.4 logged 3 stalls over the same opening section.

## Version 0.9.4

- Fixes the pairing-code loop introduced in 0.9.2 and distinguishes invalid HAP credentials from later video-session rejection.
- Verifies new authorization over an independent connection before saving it and limits renewal to one attempt per Play action.
- Removes the legacy `GET /info` request from control-stream creation: tvOS 27 rejects it even after accepting HAP, PTP, and RECORD.
- Creates remote channel type 130 with a local UUID, matching pyatv's current AirPlay 2 path, while keeping video, audio, and subtitles outside negotiation.
- Updates RTSP session identity consistently to macOS 27 and uses the AirPlay agent expected by the modern queue.
- Physically validated on Apple TV 4K with tvOS 27.0: Dolby Vision, E-AC-3, selectable subtitles, real position, pause, resume, and stop without asking for another code.

## Version 0.9.3

- Checks credentials directly with Apple TV before creating the VOD, so expired authorization no longer requires preparing the entire movie first.
- Removes a Keychain credential only when tvOS confirms that it is invalid, then requests clean authorization.
- Allows at most one automatic renewal per attempt. If tvOS also rejects the new credential, AirCiller stops and explains why instead of repeating code–VOD indefinitely.
- Keeps the HDR/Dolby Vision MP4 and HLS/fMP4 paths separate and unchanged; the fix affects only AirPlay 2 negotiation.
- Adapts the standalone build to the macOS 27 toolchain without relying on the SwiftUIMacros plugin missing from Command Line Tools.

## Version 0.9.2

- Supports MKV, MP4, M4V, and MOV with HEVC/H.265 or H.264.
- Prepares a complete, finalized HLS VOD before playback so Apple TV receives the final duration instead of a live indicator.
- Adds ±10/±30-second skips, chapters, and per-file resume positions.
- Adds audio selection, timing adjustment, and Original/E-AC-3 5.1/AAC stereo output choices.
- Adds internal and external SRT/ASS/SSA/VTT subtitles, Blu-ray PGS through local OCR, and subtitle timing adjustment.
- Preserves ASS/SSA position, alignment, margins, line breaks, bold, italic, and underline in the WebVTT path; karaoke, movement, rotation, and drawings are explained and simplified to static text.
- Converts PGS on demand with FFmpeg 9.0.1 and Apple Vision: preserves timing and approximate position, creates selectable WebVTT, reuses a local cache, and never burns text, uploads data, or modifies the original.
- Identifies DVD VobSub and explains that it still needs its own decoder; it is not confused with PGS or converted silently.
- Adds 4K, Dolby Vision/HDR, Atmos/5.1, and subtitle-count indicators.
- Adds stable recent-item ordering, a persistent reorderable playlist, consecutive playback, network checks, and compatibility messages.
- Adds multi-file opening, drag and drop, and Finder's Open with AirCiller workflow.
- Never transcodes video, and never converts audio without an explicit selection or confirmation.
- Completes packaging before playback; closing the window quits the app and removes the temporary VOD.
- Checks free space in advance and never silently reduces, changes, or transcodes the file.

### Blu-ray PGS subtitles in 0.9.2

- Decodes only the selected PGS track into transparent images; video never passes through a decoder or encoder.
- Recognizes text locally with Apple Vision and converts each composition into selectable WebVTT without a network or external service.
- Preserves Blu-ray timing, removes repeated states, and maps the graphic box into WebVTT coordinates for upper signs, lower dialogue, and side text.
- Stores the small WebVTT result in AirCiller's cache, keyed by file, modification date, size, track, and language. The first full pass takes time; later passes reuse it.
- Limits Vision to four concurrent recognition jobs and displays completed/total cues during preparation, accelerating large tracks without a permanent server or process.
- Works in both HLS/fMP4 and HDR/Dolby Vision MP4; video remains an exact copy in either case.
- Locally validated with a complete 258-cue PGS track: 8.4 seconds, 100% mean Vision confidence on that track, timing matching its reference SRT, and a second load from cache.
- Locally validated in a 120-second Dolby Vision MP4: AVPlayer sees DV video, audio, and the PGS-derived subtitle as a selectable track.
- Physically validated on Apple TV 4K with tvOS 26.6: stable playback, synchronized slider, and correctly positioned converted PGS subtitles in the lower area.

### Advanced ASS/SSA subtitles in 0.9.1

- Maps ASS/SSA coordinates and alignments to native WebVTT positions, including margins, all nine `\\an` anchors, `\\pos(x,y)` coordinates, and legacy SSA alignments.
- Preserves line breaks, bold, italic, and underline without transcoding video.
- Keeps karaoke text and moving effects at their initial position, while explaining that animation, rotation, and vector drawings are simplified.
- Adds horizontal and vertical anchors so upper signs, side notes, and lower dialogue are not clipped at the edges.
- Keeps the track selectable inside MP4 for HDR/Dolby Vision and warns that Apple TV simplifies the design; the working direct path is not altered.

### Internal modernization in 0.9.0

- Migrates interface state from `ObservableObject`/`@Published` to Observation and `@Observable`, available since macOS 14. Views now invalidate only when values they read change, so the playback clock no longer rebuilds the whole library.
- Adopts Swift 6 as the official language mode, with strict concurrency and every warning treated as an error.
- Replaces the local server's obsolete C conversion with safe, current UTF-8 decoding.
- Separates the reorderable Playlist row from the main navigation tree to reduce compile cost and isolate gestures and context menus.
- Centralizes private diagnostic and automatic-start options, with a dedicated test for incomplete arguments.
- Unifies output accumulators for `ffprobe`, FFmpeg, and the AirPlay engine while retaining memory limits and removing duplicate implementations.
- Centralizes the common session-start lifecycle without mixing the two validated media paths: direct HDR MP4 with subtitles and HLS/fMP4 VOD.
- Removes unused visual telemetry and obsolete Glass modifiers left behind after the redesign.
- Builds with dead-code stripping and is validated with FFmpeg 9.0.1.

### Stream Intelligence in 0.7.0

- Preserves the native path: copied HEVC/H.264 without transcoding, fMP4/HLS VOD or fast-start MP4, and direct AirPlay 2 control through pyatv 0.18.0.
- Analyzes every packet in the file in the background and measures average demand plus the real six-second-window peak, including the selected audio track.
- Calculates a safe network target with 50% headroom over the peak; file average is no longer presented as a sufficient requirement.
- Instruments the local server with delivered bytes, observed throughput to Apple TV, transfers, ranges normally cancelled by AVPlayer, and unexpected errors.
- Compares demand with throughput during playback and rates the margin as excellent, ready, tight, or insufficient.
- Counts buffer stalls reported by Apple TV itself and keeps a technical record per transfer for real-case diagnosis.
- Measures the Mac–Apple TV LAN and does not confuse it with an Internet speed test.
- Does not create lower-quality variants or modify video. Any future adaptive conversion must be explicit and authorized.

### Native track controls in 0.6.3

- Moves audio and subtitles from the global toolbar to player controls beside the content they affect.
- Replaces the generic settings symbol with `captions.bubble`, the semantic SF Symbol for captions and language options.
- Keeps neutral system Liquid Glass material, native hover help, and a native popover.
- Keeps the central transport group geometrically centered even when actions appear on the right.

### Visual correction in 0.6.2

- Removes inherited yellow from the entire control tree: player, slider, progress, toolbar, and selection use native macOS materials and accent.
- All player buttons use neutral Liquid Glass. The central control is distinguished only by size and position.
- Keeps yellow outside the material as identity in the icon, small library glyphs, and informational accents.
- Uses semantic red for Stop only when the action is available.

### Fixes and refinement in 0.6.1

- Makes the entire Playlist and Recents controls clickable, not only their icons or labels.
- Replaces implicit list reordering with real drag handles and insertion lines showing the exact destination.
- Removes the redundant “drag to reorder” text; the handle communicates the interaction.
- Correctly identifies scope movies at 3840×1608, 4096×1716, and equivalent dimensions as 4K instead of relying only on 2160-pixel height.
- Replaces ambiguous capsules with four editorial facts: resolution and dimensions, dynamic range and profile, audio and format, subtitles and active track.
- Writes `Dolby Vision` and `Profile 8.1` in full instead of abbreviating `DV P8` or highlighting it in yellow without meaning.
- Places transport and timeline over the image in clear Liquid Glass and applies native Glass buttons to each control on macOS 26/27.
- Keeps a single window when opening movies from Finder instead of creating a second visual copy of AirCiller.

### Redesign in 0.6.0

- Adopts macOS 27 navigation with a real sidebar, system toolbar, and native Liquid Glass in the control layer.
- Keeps content on standard materials to preserve hierarchy, contrast, and legibility in line with Apple's guidance.
- Reorganizes the movie as the main content: full title, Apple TV state, picture, format, transport, and diagnostics are readable at a glance.
- Moves network, Apple TV selection, tracks, and file opening to the toolbar; playback controls stay together in a floating glass piece.
- Uses yellow only for identity, selection, and the primary action, with automatic support for light/dark appearances, contrast, and reduced transparency.
- Renews the library with Music/Mail-style navigation, Playlist by default, full filenames, clear selection, and persistent reordering.
- Introduces a two-color yellow icon with restrained depth and an original send-to-screen mark readable at every Dock size.
- Keeps functional iconography inside the interface and reserves the original AirCiller icon for app identity.

### Fixes in 0.5.3

- Serves every session from a private random address that ceases to exist on completion; another local-network device cannot guess the movie path.
- Disables caching of served content so macOS or tvOS cannot reuse segments from a previous session.
- Continuously drains both events and diagnostics from the AirPlay engine, preventing a long warning burst from filling a pipe and freezing the connection.
- Caps diagnostic memory and retains only the useful tail when an error occurs.
- Checks Keychain authorization away from the UI thread and caches it per receiver, preventing the macOS prompt from freezing the window or repeating on every redraw.
- Expires an abandoned pairing PIN after three minutes and allows requesting another with an understandable message.
- Cancels the server correctly even if playback is interrupted while obtaining its port and network address.
- Adopts strict Swift concurrency checking and fixes a mutable capture that becomes an error in Swift 6.
- Builds and signs the complete app in a separate location, verifies it, and only then replaces the installed version; a failed build cannot leave a partial app.
- Prevents installation over a running AirCiller instance, avoiding accidental testing of the older binary macOS still has in memory.
- Keeps pyatv 0.18.0, the latest official release, and exposes useful engine warnings while hiding only the known LibreSSL warning from macOS's bundled Python.
- Verified with real files: Dolby Vision with E-AC-3 5.1 and internal subtitles; Dolby Vision with Atmos and English SDH; and H.264/AAC SDR through HLS VOD.

### Fixes in 0.5.2

- Isolates each playback and pairing session so late shutdown from an earlier session cannot clear state, slider, or the next control channel.
- Cancels the previous connection wait when rapidly changing movies or tracks, avoiding suspended tasks and retained temporary VODs.
- Distinguishes expired AirPlay credentials from real playback rejection; if tvOS requests renewed authorization, AirCiller shows the code and retries after pairing.
- Separates accepted pause, resume, and seek commands from states reported spontaneously by Apple TV; the slider corrects itself using the position confirmed by each event.
- Keeps `Playing` visible when title and artwork arrive a moment later.
- Briefly waits for macOS to confirm the network before automatic startup, avoiding false failures when opening and immediately playing.
- Hides `Resume from…` when the movie has finished and treats player HTTP range changes as normal closes rather than red failures.
- Adds explicit diagnostics for start, pause, resume, stop, and completion confirmed by Apple TV.
- Physically verified on tvOS 26.6 with a Dolby Vision P8 excerpt: E-AC-3 5.1, internal subtitles, complete duration and slider, accepted metadata, and clean completion.

### Changes in 0.5.1

- Publishes the real movie title to Apple TV/iPhone Now Playing through AirPlay 2's modern MediaRemote metadata channel.
- Sends the yellow AirCiller icon as artwork and also displays it in macOS Now Playing.
- Keeps metadata separate from video so playback continues unchanged if a receiver rejects title or artwork.
- Publishes metadata only after tvOS confirms playback and serializes every command with AirPlay 2 feedback.

### Changes in 0.5.0

- Synchronizes pauses, resumes, and seeks made with the Apple TV remote back to AirCiller, including when tvOS expresses time as an AirPlay 2 structure instead of plain seconds.
- Distinguishes finishing a movie from leaving it with the remote: only true completion advances the playlist; leaving preserves the resume point.
- Publishes title, duration, position, and state to native macOS Now Playing and accepts play, pause, skip, seek, and stop from it.
- Adds title and duration to the movie inserted into the AirPlay 2 queue so Apple TV and remote surfaces receive useful metadata.
- Disables AirCiller media controls when idle so it does not take over media keys from other apps.

### Changes in 0.4.3

- Shows the original name of each track beside its localized interpretation, for example `English SDH — Inglés SDH`.
- Does the same for audio while keeping codec, Atmos, or channel count visible.
- Adds a persistent preferred subtitle language. In 0.4.3 it preferred plain text, used SDH when that was the only compatible choice, and did not yet enable PGS/VobSub automatically.
- Explains SDH inside the track selector.
- Replaces the ambiguous `Continue` marker with `Resume from 00:53` and removes the redundant gray footer note.
- Widens the track selector so full names remain readable.

### Fixes in 0.4.2

- Adds text subtitles to HDR10 and Dolby Vision without transcoding video: AirCiller creates a fast-start MP4 with the selected video, audio, and selectable text track.
- Keeps AirPlay 2 and pyatv's remote queue; it does not use legacy AirPlay transport or require an Apple TV app.
- Preserves track selection, internal or external subtitles, and ±10-second timing adjustment.
- Preserves the direct MP4 brand and injects static HDR10 metadata when appropriate, also correcting indices shifted by the enlarged header.
- Verifies before sending that AVPlayer sees duration, audio, and a genuinely selectable subtitle track.
- Places complete duration and index information at the beginning of the subtitled MP4 so tvOS does not scan a large movie before playback.
- Reserves 16 MB for the header and adds HDR metadata there, avoiding a second full copy or loading the complete file into memory after packaging.
- Serves MP4 and HTTP ranges progressively in 1 MB blocks; an open 20 GB request no longer tries to reserve 20 GB of RAM.
- Physically verified with a 20.59 GB file: Dolby Vision, E-AC-3 5.1, and internal subtitles visible on Apple TV, with full duration and a moving slider.
- Discards the HDR master-playlist plus WebVTT approach: tvOS downloaded the playlist and variant but rejected Dolby Vision before requesting its media header.

### Fixes in 0.4.0

- Uses a direct multiplexed HLS fMP4 rendition for HDR10 and Dolby Vision 8.1. tvOS can no longer discard the movie in the master playlist's faulty variant filter.
- Preserves the HEVC/Dolby Vision bitstream and selected compatible audio; video is not transcoded.
- Fixes the FFmpeg-produced header by marking the initialization segment as `hlsf` and adding Apple's required static HDR10 metadata to `hvcC`.
- Physically verified on Apple TV with tvOS 26.6: Dolby Vision profile 8.1 and E-AC-3 5.1, with continuous header and fragment downloads.
- Keeps alternate audio and selectable WebVTT through a master playlist for SDR.
- Version 0.4.0 deliberately stopped subtitles in HDR/Dolby Vision because tvOS rejected the master playlist; 0.4.1 integrated them into MP4, and 0.4.2 fixed the infinite wait using a fast-start header with real duration.
- Test mode waits for Apple TV discovery to complete before probing and starting the file.
- Direct HDR validation no longer requires the master playlist that this path deliberately removes; that check had prevented the isolated solution from running in the app.
- Calculates HLS bandwidth from the real size and duration of all fragments instead of multiplying the file average, fixing aborts in scenes whose peak is far above average bitrate.
- Removes the false I-frame rendition that reused full segments as if they contained only keyframes.

### Fixes in 0.3.9

- Uses a synchronized clock that starts only after Apple TV confirms playback and adjusts on pause, resume, or seek.
- tvOS events without a position no longer reset time to `00:00`.
- Investigated direct MP4 delivery for Dolby Vision; later physical tests showed AVPlayer/tvOS did not accept it reliably, so 0.4.0 replaced it with direct fMP4 HLS.
- Preserved the Dolby Vision track and selected audio without transcoding during that investigation.
- Added duration and track-preservation validation that isolated the container rejection.

### Fixes in 0.3.8

- Adopts the AirPlay 2 video flow verified on Apple TV 4K with tvOS 26.6: authentication, PTP session with clock peers, `RECORD`, remote channel `type 130`, and the `/command` queue.
- Obtains `psi` from `/info` and registers channel `psi-RCS-1`, completing the Apple TV control session.
- Sends insertion, temporal interest, and playback before starting feedback; tvOS silently closed the connection when both request classes overlapped.
- Replaces invalid `/playback-info` polling with states sent by Apple TV over the AirPlay 2 event channel.
- Restores fMP4/CMAF HLS with version 7 playlists, MP4 headers, and `.m4s` segments; HEVC and Dolby Vision are no longer wrapped in MPEG-TS.
- Delivers HLS playlists without gzip, matching Apple's reference CDN, and ignores speculative connections that tvOS closes before sending a request.
- Fixes Atmos signaling to `ec-3` with `CHANNELS="16/JOC"` and keeps WebVTT as a selectable rendition.
- Experimented with an `I-FRAME-STREAM-INF` rendition; 0.4.0 removed it after confirming that reusing complete segments is not a valid I-frame track.
- Announces Dolby Vision 8.1's HDR10 base with the exact HEVC identifier and enhancement through `SUPPLEMENTAL-CODECS="dvh1.08.xx/db1p"`.
- Corrects the last segment when a test cut leaves a video tail shorter than the audio/video duration difference.
- Locally verified with Dolby Vision 5 + Atmos and Dolby Vision 8.1 HDR, both without subtitles and with a selectable internal track.
- The full transport was physically verified with H.264 and HEVC Main 10; the I-frame + Dolby Vision combination was pending acceptance after the Keychain prompt from the new build.

### Fixes in 0.3.7

- Replaces pyatv's abbreviated video startup with a complete native AirPlay 2 queue session.
- Creates an authenticated session, opens the event channel, and negotiates control stream `type 130` with its `streamID` before inserting the movie.
- Uses AirPlay 2 queue commands for play, pause, resume, and seek; no legacy transport is introduced.
- Implements HLS 6 delivery with MPEG-TS segments for Apple TV while preserving HEVC/Dolby Vision and E-AC-3 without transcoding.
- Removes `SUPPLEMENTAL-CODECS` from the AirPlay manifest; the bitstream retains Dolby Vision information and `VIDEO-RANGE=PQ` announces its HDR base.
- Adds understandable diagnostic states for session, control stream, queue insertion, and actual playback start.

### Fixes in 0.3.4

- Finishes every HTTP response through the final `Network.framework` context, allowing TCP to deliver headers and segments fully before releasing the connection.
- Avoids immediately cancelling connections with pending data. This fixed a real local-server bug, although physical testing confirmed it was not the primary cause of Apple TV rejection.
- Serves diagnostic MPEG-TS segments with the correct `video/mp2t` type.
- Logs each request's client endpoint to distinguish Apple TV unambiguously from the local player.

### Fixes in 0.3.3

- Corrects Dolby Vision profile 8.1 signaling for tvOS: the HDR10 layer is announced as `hvc1`, with Dolby Vision in `SUPPLEMENTAL-CODECS` using Apple's required `db1p` brand.
- Separates E-AC-3/AC-3/AAC audio into its own HLS rendition instead of multiplexing multichannel audio into video segments.
- Validates video and audio separately as complete, finalized VODs with headers and segments present.
- Aligns `TARGETDURATION` across renditions and delivers gzip-compressed HLS playlists as required by Apple's authoring specification.
- Preserves Dolby Vision metadata when changing the MP4 sample entry to the `hvc1` base; video remains untranscoded.
- Persistently records Apple TV requests and AVPlayer errors for physical rejection diagnosis.

### Changes in 0.3.2

- Makes Playlist the first and default view.
- Uses Recents-style cards in Playlist, preserves drag reordering, and shows full filenames.
- Stops truncating long names in Recents.
- Adds a context-menu action to start immediately from `00:00`; Playlist also allows resuming.

### Fixes in 0.3.1

- Restores atomic HTTP responses. Version 0.3 split headers and bodies across TCP sends; this fix was necessary but did not by itself resolve the incorrect Dolby Vision 8.1 signaling corrected in 0.3.3.
- Adds traces for every HLS request so future incidents can distinguish format rejection from a network problem.

### Fixes in 0.3

- Prevents old sessions from reappearing after switching movies or skipping quickly.
- Uses aligned, complete VOD playlists with `#EXT-X-ENDLIST` for video, audio, and subtitles.
- Declares Dolby Vision profile/level, PQ range, and video/audio codecs in the master playlist.
- Segments WebVTT on the same timeline as video and covers intervals without text.
- Ensures pausing does not leave FFmpeg running because packaging has already completed.
- Supports HEAD and range requests, rejects invalid ranges, and sends segments in blocks without loading them entirely into memory.
- Removes baked WebVTT styling so Apple TV preferences control size and position.
- Preserves files received through Open with AirCiller while the window finishes starting.
- Explains and cleans the session if FFmpeg exits during preparation.
- Opening a recent movie no longer changes its position; only explicit actions reorder the playlist.
- Adds a native ICNS with Retina representations, optical margin, shadow, transparency, and a continuous silhouette, removing the yellow square in the Dock.
- Drains FFmpeg output while reading metadata and extracting subtitles, preventing deadlocks with complex files or many tracks.
- Removes entries whose files no longer exist from both persistent history and playlist.

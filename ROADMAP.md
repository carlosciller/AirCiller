# Technical roadmap

The priority is measurable robustness, not adding features for their own sake.

## Next isolated fixes

1. [x] Unify FFmpeg/ffprobe execution behind a cancellable process so Stop or switching files immediately ends abandoned analysis, preparation, and OCR work.
2. Add a synthetic attached-artwork fixture and always select/map the exact index of the real video stream.
3. [x] Select the local address from the effective route to the Apple TV on Macs with multiple interfaces or a VPN, while keeping the current behavior as a fallback.
4. Add characterization tests for the AirPlay controller, Keychain races, and corrupt persistence before splitting the large coordinator files.

Each playback change must be validated locally first, then independently through direct MP4 and HLS/fMP4, and finally on a physical Apple TV before installation.

## Maintenance and publication

- [x] Use English as the development language with a complete native Spanish localization that follows the macOS language setting.
- [x] Publish the main documentation and GitHub templates in English while keeping a Spanish README.
- [ ] Add a reproducible process for regenerating and verifying `requirements.lock`; major upgrades such as protobuf 7 require an updated lock, full local checks, and physical validation when they can affect the AirPlay engine.
- [ ] Enable GitHub private vulnerability reporting.
- [x] Create the first version tag and private release after the localized build passes the physical Apple TV matrix.

## Functional candidates

1. [x] Reuse the Apple Vision pipeline for local, on-demand DVD VobSub OCR.
2. [x] Add a visible limit and controls for prepared-media and subtitle caches.

## Out of scope

- Telemetry or analytics.
- Cloud storage or uploading movies/subtitles.
- A permanent server or background indexing.
- Silent transcoding.
- Heavy dependencies without a demonstrated benefit.

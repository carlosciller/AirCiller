# Contributing to AirCiller

AirCiller is a personal project, but focused reviews and small proposals are welcome.

## Before proposing a change

- Keep opening a file and starting playback fast and lightweight.
- Do not add telemetry, cloud services, a permanent server, or background work.
- Do not modify originals or transcode silently.
- Do not change direct MP4 and HLS/fMP4 in the same delivery.
- Do not include movies, commercial subtitles, network addresses, device names, or credentials.

## Minimum validation

1. Run `./Scripts/check.sh`.
2. Build with `./build.sh` using strict Swift 6 and warnings-as-errors.
3. State clearly which tests are local and which were performed on a physical Apple TV.
4. For playback changes, validate the two paths in [TESTING.md](TESTING.md) separately.

Changes produced with AI tools are acceptable, but they must be reviewed, understandable, and held to the same validation standard as any other change.

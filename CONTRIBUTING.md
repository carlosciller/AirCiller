# Contributing to AirCiller

AirCiller is a personal project, but focused reviews and small proposals are welcome.

## Before proposing a change

- Keep opening a file and starting playback fast and lightweight.
- Do not add telemetry, cloud services, a permanent server, or background work.
- Do not modify originals or transcode silently.
- Do not change direct MP4 and HLS/fMP4 in the same delivery.
- Do not include movies, commercial subtitles, network addresses, device names, or credentials.

## Minimum validation

For documentation-only changes, review the diff, verify referenced paths and consistency, and run `git diff --check`. No app build or physical playback is required unless executable behavior also changes.

For code, dependency, or build changes:

1. Run `./Scripts/check.sh`. It already invokes `./build.sh` using strict Swift 6 and warnings-as-errors; a second identical build is unnecessary after it passes.
2. State clearly which tests are local and which were performed on a physical Apple TV.
3. For playback changes, validate the affected cases in [TESTING.md](TESTING.md), keeping the two paths separate. Engine upgrades require both paths.

Add tests for meaningful changed behavior. Once required checks pass, repeat or broaden validation only when new changes, failures, or unresolved concerns justify it.

Changes produced with AI tools are acceptable, but they must be reviewed, understandable, and held to the same validation standard as any other change.

## Python dependency changes

Edit `requirements.in`, then regenerate the lock with:

```sh
./Scripts/requirements_lock.sh update
```

The script uses fixed Python, pip and pip-tools versions and writes the lock atomically. Use `upgrade` instead of `update` only for an intentional review of every transitive dependency. Do not edit `requirements.lock` by hand. `./Scripts/check.sh` verifies that the committed lock can be reproduced before building the app.

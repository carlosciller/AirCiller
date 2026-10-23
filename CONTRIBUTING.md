# Contributing to AirCiller

AirCiller is a personal project, but focused reviews and small proposals are welcome.

## Before proposing a change

- Keep opening a file and starting playback fast and lightweight.
- Do not add telemetry, cloud-library services or unrelated background work.
  The separately provisioned [private-control integration](Docs/PRIVATE_REMOTE_CONTROL.md)
  is opt-in and is not deployed by an ordinary app build or release.
- Do not modify originals or transcode silently.
- Do not change both the direct MP4 and HLS/fMP4 packagers in one delivery. Shared controls or server changes require assessing and validating their effects on both paths.
- Do not include movies, commercial subtitles, network addresses, device names, or credentials.

## Prepare a checkout

Use an Apple silicon Mac with the Swift 6 Command Line Tools and the Node version
in `.node-version` for private-control tests. Put that Node executable on PATH or
set `AIRCILLER_NODE` to its absolute path. Node is a development/service dependency,
not an addition to the app bundle. Start from the intended revision in a clean
clone or worktree; inspect `git status --short` and preserve any existing work.
Do not copy another checkout's build output or local signing configuration into
a clean release checkout.

Prepare the dependencies from the repository root:

```sh
brew bundle
./Scripts/bootstrap_dependencies.sh
./Scripts/bootstrap_sparkle.sh
./Scripts/bootstrap_engine.sh
```

These scripts prepare the locked Python packages and verified Sparkle and playback-engine archives. Do not replace them with arbitrary host packages or regenerate dependency locks just to build. Record `git rev-parse HEAD`, `sw_vers`, `xcodebuild -version` and `xcrun swiftc --version` with validation results. This makes the inputs and environment traceable; it does not promise byte-identical signed bundles across machines.

For a release, finish versioning and release documentation before running the final check below. [DISTRIBUTION.md](DISTRIBUTION.md#release-procedure) defines the public signing configuration and the remaining release gates.

## Minimum validation

For documentation-only changes, review the diff, verify referenced paths and consistency, and run `git diff --check`, including new files in the review. No app build or playback session is required unless executable behavior also changes.

For code, dependency, or build changes:

Select checks before implementation using [TESTING.md](TESTING.md#choose-checks-from-the-change).
The local full gate below remains required once on the final code candidate;
focused regressions are for iteration. CI can reuse an identical successful full
check as documented there. CI-only tooling changes need no Apple TV session.

1. Run `./Scripts/check.sh` on the final candidate. It already invokes `./build.sh` using strict Swift 6 and warnings-as-errors; a second identical build is unnecessary after it passes. Keep focused regression tests for iteration before this full gate.
2. Identify the candidate and distinguish local or simulated tests, receiver state, captured digital output, and physical observation. A receiver reporting playback does not establish that picture, sound or subtitles reached the screen.
3. For playback changes, validate the affected cases in [TESTING.md](TESTING.md), keeping the two paths separate. Engine upgrades require both paths. Record failures and missing observations explicitly; neither is a pass.

Add tests for meaningful changed behavior. Once required checks pass, repeat or broaden validation only when new changes, failures, or unresolved concerns justify it. A documentation-only follow-up does not require rebuilding an unchanged binary; explain which candidate evidence remains applicable.

Changes produced with AI tools are acceptable, but they must be reviewed, understandable, and held to the same validation standard as any other change.

## Generated test storage

`benchmark_startup.sh`, `benchmark_performance.sh` and the `playback_checks.py`
launcher automatically register their generated runs. After success or failure,
the storage guard removes generated media, compiled Mach-O tools and disposable
packages from those runs. Reports, hashes, source snapshots, subtitles and
screenshots remain at their original paths, with a `.airciller-test-storage.json`
record of removed payloads. Replaying an old run may require regenerating its
synthetic media; retained measurements are not fresh playback acceptance.

Before a guarded run or `check.sh`, completed registered runs are pruned. If
`.build` still occupies 12 GiB or more, no new test starts. This is an admission
limit, not a filesystem quota: one active test can temporarily exceed it.
Reports are never deleted to satisfy the limit. Investigate the remaining usage
instead of raising it. No timer, background service or device access is involved.

The cleaner does not traverse symlinks or touch unregistered/active runs, current
tools, release archives, credentials, installed apps, original media or rollback
directories. Keep one known-good rollback outside the three managed run roots;
the local `rollback-0.17.1-to-0.17.3` copy is currently retained. Hard interruption
can leave an active run. Review it explicitly before pruning. Concurrent guarded
runs are refused.

Run `python3 Scripts/test_storage.py clean` for the same conservative cleanup.
New experimental scripts must use the guard and register their generated runs
inside an approved root; arbitrary `.build` folders are deliberately not erased.
The earlier bulk-cleanup report archive remains outside these roots.

## Python dependency changes

Edit `requirements.in`, then regenerate the lock with:

```sh
./Scripts/requirements_lock.sh update
```

The script uses fixed Python, pip and pip-tools versions and writes the lock atomically. Use `upgrade` instead of `update` only for an intentional review of every transitive dependency. Do not edit `requirements.lock` by hand. `./Scripts/check.sh` verifies that the committed lock can be reproduced before building the app.

# Build-time pip and runtime packaging

Scope: the build installer and exclusion of unused installers from the app.
No FFmpeg, CPython, pyatv, application playback source or dependency-lock update
is selected. Historic engine archives and the installed app remain unchanged.

## Finding and approach

The pinned Python archive includes pip 26.2.1 and its private certifi copy.
Updating VendorPython does not repair that copy. AirCiller imports its already
bundled dependencies; it does not invoke pip, ensurepip or package installation
during playback. The build scripts are the package-installation callers.

The [Python security announcement](https://discuss.python.org/t/109576)
identifies pip 26.2.2 as corrected and supplies an immutable wheel URL and hash.
`Scripts/build_pip.py` verifies that wheel before every use. It uses system curl
for the initial bounded download and never invokes an old installed pip to
fetch its replacement. Dependency staging uses this installer directly. The
lock compiler creates its isolated environment without ensurepip and seeds the
verified pip offline before installing its pinned tools.

`build.sh` removes only pip, its distribution metadata and command wrappers, and
ensurepip (including its bootstrap wheel) from the unsigned staged app. It
does not trim interpreter executables, extension modules, runtime dependencies,
FFmpeg or license notices. Cached engines and historical archives are retained
unchanged. Their old pip is not the installer used by the current build scripts;
they are not claimed to have been patched.

## Validation selection

- Negative control: reproduce the compromised root in the old pip trust bundle.
- Verify the corrected wheel, its CA bundle, failed/corrupt downloads and cache
  handling; run the compiler from a fresh tools directory and reproduce the
  unchanged application lock.
- Stage dependencies with the corrected installer and retain identical package
  versions. Test pruning on disposable fixtures, including symlink rejection.
- Run the complete strict local gate once after the final implementation.
- Compare the built runtime with the pinned source: retained file bytes, modes
  and symlink targets must agree; differences must be limited to the named
  installer paths and already-excluded bytecode caches.
- Verify bundled pyatv/helper imports and offline execution, app launch, strict
  signatures and size. These packaging-only checks do not require Apple TV
  playback, pairing, capture, cameras or microphones.

This is not a release or installed update.

## Initial evidence

- The old installer trust store reproduces the compromised-root finding.
  The verified 26.2.2 wheel excludes it and retains over 100 trust roots.
- The six installer and four pruning regressions pass. Against the previous
  untrimmed app, both the installer-absence and exact-runtime-inventory checks
  fail as expected; the unchanged helper/dependency comparison passes.
- A freshly created compiler environment reproduces the existing lock with pip
  26.2.2, Python 3.13.15 and pip-tools 7.6.1. No application dependency changed.
- Dependency staging through the verified installer succeeds with all 31
  hash-locked packages. Logs and negative controls are retained privately under
  `.build/pip-maintenance/`.

## Final local acceptance, 23 October 2026

Base revision: `24adf632da096a4d94c8c13042e55f7b1533fadc`. Validation ran on
macOS 27.2 (26B118), arm64, Apple Swift 6.4 from Command Line Tools. A full Xcode
installation was not selected; `xcodebuild -version` reports that distinction.

- The single final `Scripts/check.sh` run passed, including strict Swift 6,
  warnings-as-errors, every existing test, the ten focused installer/pruning
  checks and three final bundle checks. Log SHA-256:
  `4e8fa00e01589285d6944880eeb5e2075daf11983a2a33f097fd8d617f668a29`.
- Retained Python file bytes, modes and symlink targets match the pinned input.
  The staged VendorPython files and copied helper match their checked sources.
  The packaged interpreter imports pyatv and its dependencies, executes the
  helper's offline version command and cannot import pip or ensurepip.
  It can also execute the separate verified build installer when explicitly
  used as a development interpreter; no installed pip is required.
- FFmpeg and ffprobe binaries match the cached originals byte for byte. The
  historical Python and FFmpeg archives retain SHA-256 values
  `4481b749d5a147f1762026940387ed4476d71d98edf781532a8d0949ea883221` and
  `059a683433d3b05f7fe1f2231942cebeb51bbbded3cbed46da1d702f3a451c83`.
- The ordinary ad hoc candidate is 145,816,208 logical bytes. Its Python
  component is 56,843,994 bytes, down from 64,361,197 before installer exclusion:
  7,517,203 bytes of installer payload removed. The 165 MB budget is unchanged.
  Executable SHA-256:
  `f851251a05cd365ac7b90ec1c6c869d66b9b69c572b7785e7d2ec0a97df4cdd5`.
- A separate `--candidate` build was needed for the native launch check: that
  existing variant disables ordinary startup cache cleanup and updater activity.
  It was opened with device scan and private control disabled. Its empty library,
  inspector and disabled playback controls appeared, and closing it terminated
  its process. This was one isolated launch, not another full test campaign.
  Both bundles passed deep strict signature verification.
- The installed daily executable remains
  `8bbfedf3db0b197fd664251b9117978e5a29ab7e1685f115b645805aa5572a73` and its
  existing process remained running. No camera, microphone, capture, pairing,
  movie or live connector test was used.

No application source, runtime version, playback helper or application lock
changed in this work. Local acceptance does not claim new receiver output,
remote CI, publication, notarization or installed-update acceptance. Historical
archives and recovery copies still contain their original tooling; the current
build entry points no longer execute it. Future release and installation retain
their separate distribution gates.

# Third-party dependencies

AirCiller relies on independent projects that retain their own licenses:

| Project | Use | License |
| --- | --- | --- |
| [pyatv](https://github.com/postlund/pyatv) | Discovery, authentication, and the foundation of AirPlay 2 transport | MIT |
| [FFmpeg](https://ffmpeg.org/) | Local analysis and preparation of containers, audio, and subtitles | Depends on the installed build; usually LGPL or GPL |
| [Sparkle](https://sparkle-project.org/) | Secure application updates | MIT and bundled third-party notices |
| [python-build-standalone](https://github.com/astral-sh/python-build-standalone) | Redistributable CPython runtime for managed AirPlay components | MPL-2.0 build tooling; bundled CPython and library licenses remain applicable |

`Scripts/airplay_helper.py` extends and adapts pyatv's AirPlay 2 transport behavior. The corresponding MIT notice and license are preserved in [LICENSES/pyatv-MIT.md](LICENSES/pyatv-MIT.md).

Transitive Python dependencies are installed locally from `requirements.lock` and are not committed to Git. Their metadata and license texts are included in the built application when provided by the package.

AirCiller can use an existing FFmpeg installation or download AirCiller's self-contained FFmpeg build. That managed build is compiled from the official FFmpeg 9.0.1 source with no optional third-party codec libraries and includes FFmpeg's LGPL-2.1 notice. Its exact source URL, checksum and configure options are recorded in `Scripts/build_managed_components.sh`.

The optional managed Python runtime is derived from Astral's `python-build-standalone` CPython 3.13.15 distribution. Its upstream SHA-256 digest is pinned in `Scripts/build_managed_components.sh`; the upstream distribution includes CPython and bundled-library license texts.

The build downloads the official Sparkle 2.9.6 binary distribution after checking its SHA-256 digest. Sparkle's complete license file is included inside the built application.

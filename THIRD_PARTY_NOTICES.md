# Third-party dependencies

AirCiller relies on independent projects that retain their own licenses:

| Project | Use | License |
| --- | --- | --- |
| [pyatv](https://github.com/postlund/pyatv) | Discovery, authentication, and the foundation of AirPlay 2 transport | MIT |
| [FFmpeg](https://ffmpeg.org/) | Local analysis and preparation of containers, audio, and subtitles | Depends on the installed build; usually LGPL or GPL |

`Scripts/airplay_helper.py` extends and adapts pyatv's AirPlay 2 transport behavior. The corresponding MIT notice and license are preserved in [LICENSES/pyatv-MIT.md](LICENSES/pyatv-MIT.md).

Transitive Python dependencies are installed locally from `requirements.lock` and are not committed to Git. Their metadata and license texts are included in the built application when provided by the package.

AirCiller does not bundle FFmpeg binaries; it uses the existing installation on the Mac. The exact FFmpeg license depends on the options used to build that binary.

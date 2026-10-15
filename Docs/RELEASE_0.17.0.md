# AirCiller 0.17.0 release verification

Recorded on 15 October 2026. Version 0.17.0, build 65, is
[published](https://github.com/carlosciller/AirCiller/releases/tag/v0.17.0) and
installed through the native Sparkle updater. This record describes that release;
it does not certify later revisions.

## Candidate and checks

The reviewed candidate was `96824767908eeeed706423a43926e1dcd8c8997f`.
[PR #25](https://github.com/carlosciller/AirCiller/pull/25) was squash-merged as
`8284aba0efbde730117e01bc24cd44a6f1e64e2f`, and `v0.17.0` points to that commit.
The candidate and merge have identical tracked content.

The complete local `AIRCILLER_SIGNING_IDENTITY=- ./Scripts/check.sh` passed,
including the strict Swift 6 build with warnings-as-errors. Exact-revision CI
also passed:

- [Candidate pull request](https://github.com/carlosciller/AirCiller/actions/runs/38696956554)
- [Merged main](https://github.com/carlosciller/AirCiller/actions/runs/38698159609)
- [Release tag](https://github.com/carlosciller/AirCiller/actions/runs/38698165541)

Playback acceptance is recorded separately in [audio expansion](AUDIO_EXPANSION.md)
and [manual timing](HLS_AUDIO_TIMING.md). Those records retain failures, offline
reassessments and fresh captures separately. Captured digital output is not a
physical speaker, HDR-rendering or whole-movie test. The direct MP4 packager and
pinned engines are unchanged.

## Published artifacts

The signed bundle contains 156,034,955 logical file bytes, below the 165,000,000-byte
budget. Its application executable SHA-256 is
`4c4ac3173a9cef3ee0bad9e230cd777995b578649e8ccd3d4017ea6f95f44d97`.

| Asset | SHA-256 |
| --- | --- |
| `AirCiller-0.17.0-65.zip` | `475b7414eab69429f558c54b0237d00ec6f0061d88b9dc34df9eec5dfe4b04b4` |
| `AirCiller65-64.delta` | `fb7d9449d84ef74bde0aa32a6c0e2c6cdc6ec9349aa3269c8a6d4e84224acd8c` |
| `appcast.xml` | `e9e6afcf92855bc0649fab9f830cfbe4951925f3ad2f2861b051d54a4a3a930d` |
| `AirCiller-0.17.0-65.md` | `89906e2b46852c8c40741d907b765de1be1a59b449f461478654d5d98a092e91` |

The full ZIP is 64,584,760 bytes; the build-64 delta is 280,654 bytes. All four
public assets were downloaded without authentication and matched the reviewed
files. The stable latest-feed URL returned the same appcast. Sparkle verified
the downloaded feed, full archive and delta EdDSA signatures. The GitHub release
body matches the reviewed versioned notes.

Applying the delta to an isolated 0.16.0 bundle produced the accepted 0.17.0 bundle:
3,424 files, directories and symlinks matched, including file bytes, modes and
symlink targets. Strict code-signature verification passed.

The release uses the existing public ad hoc policy. It is not Developer ID
signed or notarized; the distribution audit reports those limitations separately
from signature integrity. No signing identity or credential store was changed.

## Native installation

With the previous daily-use 0.16.0/build-64 app idle, a rollback bundle and private
preference snapshot were retained. **Check for Updates…** detected 0.17.0, displayed
its release notes, downloaded the update and offered **Install and Relaunch**.
Sparkle installed it and relaunched the same daily-use app path.

The relaunched About window displayed **0.17.0 (65)**. Its installed metadata,
running executable path, strict signature and all 3,424 bundle entries matched
the accepted public package. The library was visible, the tracks inspector
remained open, and semantic comparisons confirmed unchanged recent items,
Playlist, seasons and application preferences. Only Sparkle's last-check timestamp
changed. Private library contents and preference values are not published.

The interface connection briefly disappeared while the app was being replaced;
rebinding after the native relaunch confirmed the new version. No manual bundle
copy was used as a substitute for the updater. The app was left idle, ready to use.

## Development-guide follow-up

The separate documentation follow-up centralizes checkout and local checks in
Contributing, release procedure in Distribution, and current playback requirements
in Testing. Earlier observations move to [validation history](VALIDATION_HISTORY.md)
with their failures and limitations preserved. Architecture documents the current
routes, audio policies and source/presentation clocks. Agent instructions and the
local skill point to those owners instead of repeating the complete procedures.

This follow-up changes no application code, engine, signed release asset or
installed bundle. Its checks are diff review, local links/anchors, public-text
validation and skill validation. It does not require another binary release or
Apple TV session.

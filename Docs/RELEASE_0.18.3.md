# AirCiller 0.18.3 release record

Published and installed: version 0.18.3, build 72, on 28 October 2026.
[Release](https://github.com/carlosciller/AirCiller/releases/tag/v0.18.3).

## Scope and retained evidence

PR #47 adds bounded library recovery and corrects duplicate and mixed-import
receipts. Its final commit `9aab0072e4dd9f11a2b81bce50858128a0bc8318`
passed [full CI](https://github.com/carlosciller/AirCiller/actions/runs/40754514967).
The [candidate record](LIBRARY_RELIABILITY_REVIEW.md) retains the failed receipt
baseline, passing storage/coordinator regressions and actual English/Spanish UI checks.

Release preparation changes version/build and prose only. Production sources,
resources, helpers, dependency locks and build scripts retain the accepted PR
inputs. Native recovery and import checks are reused, not repeated. Both media
packagers and runtimes are unchanged from 0.18.2; this library boundary needs no
new Apple TV session under TESTING.md. No new audiovisual claim is made.

## Distribution and installation

- PR #47 merged as `ecfe675`; its main CI passed by reusing the accepted PR evidence.
- Release PR #48 passed [full CI](https://github.com/carlosciller/AirCiller/actions/runs/40765154743).
- Release commit and tag: `097eb40aed1f7f8f344d5a8cf5707e25184527d5`.
  [Main CI](https://github.com/carlosciller/AirCiller/actions/runs/40766795021)
  passed using the identical PR evidence.
- [Tag CI](https://github.com/carlosciller/AirCiller/actions/runs/40766805829)
  passed a full run. Its hosted image was `20261013.0424.1`, different from
  the PR/main image `20261021.0445.8`; the evidence matcher correctly refused reuse.
  The tag also waited for a hosted runner. No tests or policies were weakened.
- The strict local release gate passed once on `c7e8b6e`; its tree matches the
  release commit. Log: `.build/release-0.18.3-local-check.log`.
- Bundle: 145,993,559 logical bytes, below the 165,000,000-byte limit.
  Code-signature structure and bundled runtimes passed inspection. Missing
  Developer ID, Hardened Runtime, notarization and Gatekeeper acceptance remain
  the established ad hoc distribution limitations.
- The public feed, full ZIP and five deltas match the accepted local bytes and
  pass Sparkle EdDSA verification. The signing account's public key matches the
  accepted app. Downloaded notes and the GitHub body match the versioned notes.
- The extracted public bundle passes deep strict signature verification and
  has the accepted executable hash. The latest-release feed points to 0.18.3.
- Native Sparkle offered 0.18.3 from daily 0.18.1, downloaded/extracted it, then
  completed Install and Relaunch. About displays 0.18.3 (72). The running daily
  path and installed executable match the accepted artifact.
- Playlist, Recents and seasons are byte-identical before and after updating.
  All other saved preferences are unchanged except Sparkle's last-check time.
  The native library still displays the same episodes and saved progress.
- A rollback app and preferences are retained outside generated-test cleanup.
  The initial updater offer still showed cached 0.18.2; reopening refreshed it.
  Two daily processes were observed after relaunch; closing the UI-selected
  instance left one. This does not establish whether Sparkle or UI automation
  caused the duplicate launch. No lifecycle-service change was made.

Verification files and native updater observations are retained under
`.build/release-0.18.3-verification`. No new Apple TV tests or private-control
deployment were performed. Movies and subtitle originals were not modified.

SHA-256:

- ZIP: `cda5fcbdea6dc7d40aa2365527a90bee8ba147a4273eb72aa937ae46dba57b30`.
- Release and installed executable: `afa8179101e152ee01deeaaef041082c33305ff1f53e95328d114c8a547765c4`.

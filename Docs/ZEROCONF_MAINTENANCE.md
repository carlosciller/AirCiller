# zeroconf 0.151.5 maintenance

PR #30 updates only zeroconf from 0.150.0 to 0.151.5. This is an unreleased
dependency proposal, not a replacement of the installed 0.18.0 app.

## Failure and correction

Dependabot changed `requirements.in` but not `requirements.lock`. The original
[CI failure](https://github.com/carlosciller/AirCiller/actions/runs/39961144069)
reported a non-reproducible lock and exited with code 4. The same failure was
reproduced locally before the correction; it is not a demonstrated playback bug.

The lock was regenerated with `Scripts/requirements_lock.sh update`, using the
project's Python 3.13.15, pip 26.2.1 and pip-tools 7.6.1. No hand-edited hashes,
full transitive upgrade or test exception is involved. The PR was brought up to
date with main so it retains the accepted certifi and multidict security fixes.

## Validation selection

The [upstream changelog](https://github.com/python-zeroconf/python-zeroconf/blob/0.151.5/CHANGELOG.md)
includes TXT-record semantics, service resolution, DNS parsing and interface
handling changes. PyPI supplies the CPython 3.13 Apple-silicon wheel used here.
The published package remains LGPL-2.1-or-later; its bundled notices are retained.

AirCiller's `discover` calls `pyatv.scan` with the AirPlay protocol and without
an `aiozc` instance. The pinned pyatv therefore uses its own multicast/unicast
DNS scanners. Its optional zeroconf scanners are not selected. The DNS helper
uses zeroconf's `ServiceInfo` to encode TXT data. Imports, TXT semantics and the
real discovery-to-device-description path are the affected boundary.

Selected checks:

- Reproduce the original lock failure; regenerate and check reproducibility.
- Confirm no other locked package version changed.
- Add offline integration coverage using real pyatv parsing and configuration,
  replacing only network responses: multicast, unicast and knocker cleanup,
  metadata/AirPlay 2 identification, and rejection of a zero-port service.
- Check installed/input/lock version agreement, empty versus valueless TXT
  entries, and the async service-info address API imported by pyatv.
- Run the unchanged complete strict gate once on the final candidate, with the
  added checks; verify the built bundle's own Python imports and discovery.
- Perform one read-only discovery scan without pairing, playback or capture.
  No HDR, subtitle, long-pause or media-output campaign is selected: the media
  engine, packagers, transport and application playback code are unchanged.

These checks do not constitute a new audiovisual playback result. A later
release still needs its separate distribution and installation gates.

## Evidence

The six focused integration checks pass with the candidate dependency. Running
them against the installed 0.18.0 runtime correctly fails the version-agreement
check (0.150.0 versus the proposed 0.151.5); the installed bundle is unchanged.
Only zeroconf's pinned version changes in the regenerated lock.

Full-gate, bundled-runtime and discovery outcomes are recorded in the validation
comment on [PR #30](https://github.com/carlosciller/AirCiller/pull/30), alongside
its exact-commit CI result. The original failed lock check and local logs are
retained under `.build/zeroconf-pr30/`. No release or installation is part of
this PR repair.

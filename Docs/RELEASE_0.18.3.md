# AirCiller 0.18.3 release record

Candidate: version 0.18.3, build 72. Publication and daily installation are authorized;
their acceptance will be recorded after verification.

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

The versioned release artifact needs the strict local distribution gate,
signature/size checks, signed archive and feed, public-byte verification, exact
main/tag CI and a native Sparkle update with rollback. These are not replaced by
the earlier candidate's CI. No private-control deployment is included.

# Distribution and credential review, October 2026

This record covers the working candidate based on `68410591e3786705f54938326e152be94fa564d1`.
It is a source review and focused local validation record. It does not establish
GitHub CI acceptance, publication, installation, Apple TV output or notarization.

## Fixed findings

### OpenSubtitles redirects could forward credentials

The service used an ephemeral URLSession without a redirect policy. A local
synthetic HTTP 307 redirected a POST from one origin to another: URLSession
removed Authorization, but forwarded Api-Key and the synthetic login body.
Checking a response after following the redirect cannot prevent this disclosure.

API requests now allow only HTTPS redirects to the original host on the standard
HTTPS port. Subtitle downloads allow HTTPS OpenSubtitles hosts, matching the
existing service boundary. Embedded URL credentials and nonstandard ports are
rejected. The policy is passed to each bounded request, including injected test
sessions. The subtitle response still receives its final-URL and byte-limit checks.

`OpenSubtitlesRedirectSmokeTest` exercises the real service with a synthetic
URLProtocol. API and subtitle redirects are stopped before a request reaches the
unapproved target. A negative control that omitted the task delegate followed the
redirect and failed. Existing response-limit, cancellation, hash, request and
decoding checks passed. No account credentials or live subtitle service were used.

### The local installer accepted unrelated paths

`install_local.sh` accepted arbitrary directories and its own staging/rollback
paths as destinations. It could remove or move them before discovering the bad
target. A synthetic run of the original script reproduced invalid-directory
acceptance and mutation inside the disposable fixture.

The script now requires the exact AirCiller.app destination name, rejects a source
collision, and checks bundle identity and symlinks for every item it might remove
or move before changing anything. It verifies the source signature before copying.
Five isolated regression tests cover invalid paths, unrelated bundles, recovery
items, symlinks, normal replacement and preservation of the previous app. Only
the signing and process-presence checks are stubbed; filesystem operations are
real and restricted to each test's temporary directory.

### Private-control code was outside required checks

The local gate compiled the Swift remote contracts, but omitted PrivateRemote's
JavaScript tests and native lifecycle helper. The publication scan omitted the
entire directory as well.

The gate now runs every PrivateRemote test, including the isolated HTTPS fixture,
and compiles Lifecycle.swift with Swift 6 strict concurrency and warnings as
errors. The publication scan includes PrivateRemote. Node 24.19.0 is fixed in
`.node-version`; local checks accept that executable through AIRCILLER_NODE or
PATH, and CI installs the same version. Node's actual version participates in CI
reuse identity. CI selection regressions cover the new paths and runtime identity.
The official Node distribution lists the pinned Apple silicon archive; no Node
runtime has been added to the application bundle.

## Dependency findings

All 31 vendored Python distributions matched requirements.lock at the start of
this review. FFmpeg, CPython, pyatv and Sparkle were deliberately not upgraded
solely because a different version might be available.

A live OSV batch query on 23 October 2026 returned two affected locked packages:

| Package at review | Advisory | Scope and action |
| --- | --- | --- |
| certifi 2026.7.22 | [GHSA-6q48-6c7w-9gw2](https://github.com/certifi/python-certifi/security/advisories/GHSA-6q48-6c7w-9gw2) | The CA bundle includes emSign trust affected by compromised intermediates. Upstream removed the affected roots; OSV recommends 2026.10.19 or later. A targeted trust-store update is warranted. |
| multidict 6.7.1 | [GHSA-54p9-h82j-f925](https://github.com/aio-libs/multidict/security/advisories/GHSA-54p9-h82j-f925) | C-extension reflected items-view union and subtraction can leak references. Fixed in 6.9.1. A targeted update is warranted; the affected operations were not found in the checked helper, pyatv, aiohttp or yarl Python call sites. |

### Reachability and package provenance

The helper sends video URLs through its AirPlayV2 implementation; the Mac serves
media through the Swift HTTP server. It does not directly call requests.get.
The checked pyatv source uses requests.get in its RAOP audio-source reader and
imports requests' case-insensitive header dictionary in shared HTTP support.
The current video route does not use that RAOP reader. requests obtains its CA
bundle from certifi; aiohttp's checked connector instead creates a standard
Python SSL context. Importing requests is not evidence that an HTTPS request
used the affected trust store.

The multidict native extension is present, but the vulnerable reflected union
and items-view subtraction were not found in the helper, pyatv, aiohttp or yarl
Python call sites checked. An indirect or future caller remains possible; this
is a reachability review, not proof that every input is safe. The advisory is a
reference-leak/availability issue, not a demonstrated credential disclosure.

The existing Python engine archive was checked without rebuilding it. Its
SHA-256 matches the pin in bootstrap_engine.sh. It contains CPython 3.13.15 and
pip 26.2.1, but not pyatv or the application's VendorPython directory. build.sh
copies the locked VendorPython packages separately and the AirPlay helper sets
PYTHONPATH to that directory. Imports with this configuration resolved certifi
2026.7.22 and multidict 6.7.1 from VendorPython, as expected.

There is also a separate certifi 2026.6.17 inside pip._vendor in the engine
archive. Updating the application package does not update pip's private copy.
The application does not invoke pip during playback or install dependencies at
runtime. Development-time package installation is a separate exposure and must
not be declared fixed by a VendorPython update. No claim of a complete clean
bill of health is made for the interpreter archive or its other bundled tools.

This review found affected dependencies, not evidence of exploitation or proof
that the ordinary AirPlay video path reaches either vulnerable operation.
The OSV result covers published Python package advisories, not every engine,
operating-system library or undisclosed vulnerability.

### Targeted remediation and remaining work

Following approval within the main review, certifi 2026.10.19 and multidict 6.9.1
were explicitly pinned in requirements.in. requirements_lock.sh update ran with
its fixed Python 3.13.15, pip 26.2.1 and pip-tools 7.6.1. Comparison of every lock
block confirmed that only those two package versions, their published artifact
hashes and their direct-pin annotations changed. The reproducibility check passed.
pyatv, zeroconf and all other package versions stayed fixed.

VendorPython was regenerated with the bundled CPython 3.13.15 interpreter using
the required hashes. All 31 installed distributions exactly match the new lock.
Imports resolve certifi 2026.10.19 and multidict 6.9.1 from VendorPython. The
previous VendorPython and requirement files remain recoverable under
`.build/audit-20261023/dependencies-before-security-update/`. No manually patched
vendored library or Python source build was introduced.

DependencySecurityTest adds four offline regressions. It loads the real CA
bundle and confirms that the compromised emSign ECC Root CA - G3 fingerprint is
absent while over 100 trust roots remain. It verifies requests uses that bundle.
Its two native multidict tests use weak references with non-empty operands for
both MultiDict and CIMultiDict, confirming that reflected union and subtraction
release their values. Before the update, the CA assertion and all four native
operation cases failed. Afterward, all four tests passed. They are part of check.sh.
Existing eight aiohttp ownership/compatibility tests and the AirPlay helper smoke
test also passed after the update, without contacting a receiver.

The existing CPython/FFmpeg download names, hashes and cached archives are
unchanged and their SHA-256 values were rechecked. The lock describes the
libraries copied into Resources/VendorPython, not the independent interpreter
archive. VendorPython's logical size, excluding generated bytecode, grew by
40,898 bytes. The final app size and its import provenance are still for the main
review's combined build and distribution checks; a lock update is not a release.

Treat pip's old private CA bundle separately. The
[Python security announcement](https://discuss.python.org/t/information-for-python-users-regarding-emudhra-emsign-ca-certificate-security-incident/109576)
also identifies pip 26.2.2 as a fixed package installer. A follow-up should review
updating or omitting unused packaging tools from a deliberately versioned Python
runtime artifact, with the lock compiler's pinned installer assessed separately.
If an engine archive changes, publish a new asset identity and SHA-256 and update
all bootstrap/catalogue references together. Never replace the historic v0.10.3
archive under its existing name or reuse its cache key for new bytes. Preserve a
known-good recovery candidate and verify a clean-cache bootstrap. No change to
that separate pip copy, engine artifact or installed application was made here.

The certifi advisory identifies 2026.10.18 as its first patch; the follow-up
2026.10.19 selected above is the fixed version recorded by the OSV result.
Wheel availability and Python requirements were checked against the official
[certifi metadata](https://pypi.org/pypi/certifi/2026.10.19/json) and
[multidict metadata](https://pypi.org/pypi/multidict/6.9.1/json). The subsequent
approved bootstrap installed the hash-locked wheels; no replacement interpreter
or FFmpeg engine was downloaded.

## Existing GitHub state

The main reviewer retrieved this snapshot during the audit, separately from the
uncommitted candidate's local checks:

- No open issues were returned. This does not mean the roadmap has no pending
  work or that this audit has no findings.
- main at `68410591e3786705f54938326e152be94fa564d1` had a successful
  [CI run 39309580759](https://github.com/carlosciller/AirCiller/actions/runs/39309580759).
  That result is for the existing commit, not this working candidate.
- The only open pull request was
  [#30, zeroconf 0.150.0 to 0.151.5](https://github.com/carlosciller/AirCiller/pull/30),
  at head `79af6e151dac2824e5f50bbbe0a7a328b15cca4a`.
  [Run 39221162170, job 117956529438](https://github.com/carlosciller/AirCiller/actions/runs/39221162170/job/117956529438)
  failed with exit 4 in the reproducibility check. Its log installed zeroconf
  0.150.0 from the old lock and showed a regenerated lock/hash diff. It therefore
  did not validate a coherent 0.151.5 dependency set. Do not merge it as-is or
  weaken the lock check; regenerate and validate the intended dependency set in
  a separate change. Keep this PR separate from the security pins above.

## Coverage

The source review covered these boundaries and their focused tests:

- Credential reads/writes and serialization: AirPlayCredentialStore,
  OpenSubtitlesCredentialStore, CredentialServiceClient, CredentialService/main.c;
  signing identity selection, creation and credential-service packaging.
- Authorization: AirPlayPairingIntent, AirPlayPairingLifecycle,
  AirPlayAuthorizationRetryPolicy, PlaybackAuthorizationPreflight and the
  authorization/pairing sections of AirPlayController. Existing credential-store
  and peer-verification boundaries remain in place.
- Dependencies: BundledEngine, AirPlayRuntimeProbe, ComponentManager,
  ManagedComponentModels, requirements input/lock consistency, dependency
  bootstrapping, managed-component build/archive scripts and runtime selection.
- Updating and packaging: UpdateController, UpdateConfiguration,
  UpdateAvailability, Info.plist, build.sh, package_update.sh, install_local.sh,
  check_bundle_size.py and audit_distribution.sh.
- CI and privacy: ci.yml, ci_validation.py, check.sh, publication scanning and
  existing policy regressions. PrivateRemote transport internals are covered by
  the main review, not duplicated here.
- Storage and reporting: AirCillerStorage, PreparedMediaStorage,
  PreparedMediaCache, DiagnosticsReport, test_storage.py and storage tests.
- Network credentials and downloads: OpenSubtitlesService,
  BoundedHTTPResponse and their regression tests.

The referenced code was read for concrete boundary defects. This is not a claim
that every possible interleaving or platform behavior was exhaustively tested.
The persistent credential component was neither rebuilt nor reauthorized.

## Focused validation

- OpenSubtitles redirect regression, including the negative control: passed.
- Bounded HTTP length/cancellation and OpenSubtitles parsing/request tests: passed.
- Local installer: five tests passed; the unchanged original failed the invalid
  target negative control as expected.
- CI selection: seven tests passed.
- Test storage: seven tests passed.
- Bundle-size policy: three tests passed.
- Signing-identity input handling: passed.
- Distribution audit: six synthetic cases passed.
- Dependency security: four tests passed after the targeted update; the previous
  dependencies failed the affected-root and native reference-release checks.
- aiohttp compatibility: eight tests passed; AirPlay helper smoke test passed.
- requirements.lock reproducibility and all 31 installed version matches passed.
- Native lifecycle helper: strict Swift 6 compilation passed, without executing it.
- Publication content and whitespace checks passed after the final assigned edits.

The initial private-control unit run observed the main review's new lowercase
UUID retention regression failing before its corresponding fix. The main review
owns its repaired result and the final combined gate. No real installation,
Keychain operation, capture device or television session was used by this subtask.

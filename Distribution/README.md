# Managed components

AirCiller can download its two optional runtimes from GitHub Releases:

- a self-contained FFmpeg build used for probing and media preparation;
- a standalone CPython runtime used by AirCiller's pinned AirPlay engine.

`components-v1.json` contains the exact version, architecture, minimum macOS version, download size, SHA-256 digest and executable path for every archive. `components-v1.json.sig` is an Ed25519 signature over the exact JSON bytes. AirCiller verifies the signature before reading any URL, then verifies the selected archive again before extraction.

An installation is staged under `~/Library/Application Support/AirCiller/Components`. The active version changes only after the executable and every extracted path pass validation. The previous version remains available for rollback.

The archives are built locally with `Scripts/build_managed_components.sh` and the signed catalogue is generated with `Scripts/package_managed_components.sh`. The latter uses the same private key kept by Sparkle in the maintainer's Keychain; the private key is never stored in this repository.

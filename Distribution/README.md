# Distribution files

Current releases include their playback engines. AirCiller does not download or update FFmpeg or Python separately.

## Current inputs

- `ReleaseNotes/`: notes for each app version.
- `appcast.xml.example`: signed Sparkle feed documentation.
- `Scripts/bootstrap_engine.sh`: fetches pinned, checksum-verified archives at build time.
- `Scripts/build_managed_components.sh`: builds those archives from recorded sources. Its historical filename is retained.

Scripts are relative to the repository root. See [Distribution and updates](../DISTRIBUTION.md) for packaging, signatures and publication.

## Historical component catalogue

`components-v1.json` and `components-v1.json.sig` describe separate downloads used by older releases. Keep the exact signed files and archives for auditing and reproduction. Current builds do not read this catalogue.

`Scripts/package_managed_components.sh` creates the historical archives and signs the catalogue using the maintainer's Keychain. Removing the unused installer does not remove these tools or older users' installed components.

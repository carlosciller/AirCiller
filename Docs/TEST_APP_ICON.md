# Internal app identity

AirCiller's daily app keeps its existing yellow icon. Internal app builds use a
shared diagonal variant: the upper-left half remains yellow with a white glyph;
the lower-right half is purple with the same glyph in yellow. There is no badge
or text. The outline, screen, beam, spacing and shadow come from the same
code-native renderer, `Scripts/make_icon.swift`.

## Build modes

| Command | Bundle in `.build` | Icon |
| --- | --- | --- |
| `./build.sh` | `AirCiller.app` | Production |
| `./build.sh --candidate` | `AirCiller Test.app` | Test |
| `./build.sh --playback-checks` | `AirCiller Playback Checks.app` | Test |

The candidate is the normal interface with the `AIRCILLER_UI_CHECKS` compilation
flag, without the playback-check runner. Both internal modes use the already
allowlisted `local.carlosciller.AirCiller.PlaybackChecks` credential-client
identity. Do not run them concurrently. This avoids widening credential-service
trust to another application identifier.

Internal bundles do not advertise movie-file or URL associations and have no
Sparkle feed/public key; their automatic update settings are disabled. The icon
is a visual distinction, **not a data sandbox**. Internal builds still need the
existing test launch/storage overrides when isolation is required. Neither mode
installs over the daily app, and neither changes its version or icon.

`Scripts/build_playback_capture.sh` builds command-line tools, not a Finder/Dock
app, so it needs no icon. The synthetic credential-integration and startup
benchmark bundles are also command-line fixtures. They are not user-facing
auxiliary applications.

## Other prototypes and old builds

For a newly built GUI prototype or future helper, generate this same icon before
signing, set `CFBundleIconFile` to the ICNS resource, then sign the resulting
bundle. Do not modify an existing signed bundle in place: that invalidates its
signature. Build a fresh replacement instead. Historical release archives,
Sparkle full/delta test copies and rollback apps retain their original artwork
and signatures.

To generate the two resources with the renderer compiled by the normal build:

```sh
.build/make-icon --test /explicit/output/Test.png /explicit/output/Test.icns
```

The output parent must already exist. Use the PNG for artwork/previews and the
ICNS for the app's icon. Production generation omits `--test`.

## Validation

`Tests/IconSmokeTest.swift` checks deterministic output, unchanged production
artwork, transparent margins, unchanged silhouette coverage, the matching
background/glyph diagonal and all eight PNG-backed ICNS representations. It
writes private previews at 32, 64, 128, 256, 512 and 1024 pixels under
`.build/tests/icon-output`. Inspect the small previews and the running internal
app's Dock icon in addition to the automated checks. An icon change does not
establish playback acceptance.

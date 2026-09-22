#!/usr/bin/env python3
"""Prepare Swift constant extraction and package Apple's App Intents metadata.

The metadata processor ships with Xcode, not Command Line Tools. Its invocation
follows Swift Build's AppIntentsMetadata.xcspec. Never execute the app to extract
metadata or substitute a hand-written action manifest for Apple's output.
"""

import argparse
import json
import plistlib
import subprocess
import sys
from pathlib import Path


MODULE_NAME = "AirCiller"
TARGET = "arm64-apple-macosx14.0"
PROTOCOLS = ["AppIntent", "AppEntity", "AppEnum", "EntityQuery", "AppShortcutsProvider"]
INTENTS = {
    "OpenMovieIntent", "SendMovieToAppleTVIntent", "AddMovieToPlaylistIntent",
    "PauseAirCillerIntent", "ResumeAirCillerIntent", "StopAirCillerIntent",
}


def extraction_paths(intermediates: Path) -> tuple[Path, Path, Path]:
    return (
        intermediates / "output-map.json",
        intermediates / "protocols.json",
        intermediates / "ShortcutsIntents.swiftconstvalues",
    )


def prepare(source: Path, intermediates: Path) -> None:
    if not source.is_file():
        raise ValueError("The Shortcuts intent source is missing.")
    intermediates.mkdir(parents=True, exist_ok=True)
    output_map, protocols, constants = extraction_paths(intermediates)
    output_map.write_text(
        json.dumps({str(source.resolve()): {"const-values": str(constants.resolve())}}) + "\n",
        encoding="utf-8",
    )
    protocols.write_text(json.dumps(PROTOCOLS) + "\n", encoding="utf-8")
    # A failed compiler invocation must not leave an older extraction reusable.
    constants.unlink(missing_ok=True)


def extract(
    *, source: Path, intermediates: Path, app: Path, processor: Path,
    sdk: Path, toolchain: Path, xcode_version: str,
) -> None:
    contents = app / "Contents"
    resources = contents / "Resources"
    binary = contents / "MacOS" / "AirCiller"
    _, _, constants = extraction_paths(intermediates)
    for path in (source, processor, binary, constants, contents / "Info.plist"):
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"Missing App Intents build input: {path.name}")
    with (contents / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    bundle_identifier = info.get("CFBundleIdentifier")
    allowed_bundle = bundle_identifier == "local.carlosciller.AirCiller"
    allowed_candidate = (
        bundle_identifier == "local.carlosciller.AirCiller.PlaybackChecks"
        and info.get("ACDevelopmentBuild") is True
        and info.get("CFBundleDisplayName") == "AirCiller Test"
    )
    if not (allowed_bundle or allowed_candidate):
        raise ValueError("App Intents metadata is only supported for AirCiller or its UI candidate.")
    values = json.loads(constants.read_text(encoding="utf-8"))
    if not isinstance(values, list) or not any(
        "AppIntents.AppIntent" in item.get("conformances", [])
        for item in values if isinstance(item, dict)
    ):
        raise ValueError("Swift extracted no App Intents. Refusing to package empty Shortcuts support.")
    extracted = {
        item.get("typeName") for item in values if isinstance(item, dict)
        and "AppIntents.AppIntent" in item.get("conformances", [])
    }
    if extracted != {f"{MODULE_NAME}.{intent}" for intent in INTENTS}:
        raise ValueError("Swift did not extract all six AirCiller actions with the correct module identity.")
    metadata = resources / "Metadata.appintents"
    if metadata.exists():
        raise ValueError("App Intents metadata must be extracted into a fresh staged bundle.")
    command = [
        str(processor), "--toolchain-dir", str(toolchain),
        "--module-name", MODULE_NAME, "--sdk-root", str(sdk),
        "--xcode-version", xcode_version, "--platform-family", "macOS",
        "--deployment-target", "14.0", "--target-triple", TARGET,
        "--bundle-identifier", bundle_identifier, "--binary-file", str(binary),
        "--source-files", str(source), "--swift-const-vals", str(constants),
        "--compile-time-extraction", "--no-app-shortcuts-localization",
        "--output", str(resources),
    ]
    subprocess.run(command, check=True)
    for filename in ("extract.actionsdata", "version.json"):
        output = metadata / filename
        if not output.is_file() or output.stat().st_size == 0:
            raise ValueError(f"Apple's App Intents processor did not produce {filename}.")
    json.loads((metadata / "version.json").read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    prepare_parser = subparsers.add_parser("prepare")
    extract_parser = subparsers.add_parser("extract")
    for command_parser in (prepare_parser, extract_parser):
        command_parser.add_argument("--source", type=Path, required=True)
        command_parser.add_argument("--intermediates", type=Path, required=True)
    for argument in ("app", "processor", "sdk", "toolchain"):
        extract_parser.add_argument(f"--{argument}", type=Path, required=True)
    extract_parser.add_argument("--xcode-version", required=True)
    args = vars(parser.parse_args())
    command = args.pop("command")
    try:
        if command == "prepare":
            prepare(**args)
        else:
            extract(**args)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"App Intents metadata: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

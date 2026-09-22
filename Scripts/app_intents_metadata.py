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
ACTION_CONTRACTS = {
    "OpenMovieIntent": {
        "title": "Open Movie", "parameters": {"movie": ("Movie", False)},
        "summary": "Open ${movie}", "other_parameters": [],
    },
    "SendMovieToAppleTVIntent": {
        "title": "Send Movie to Apple TV",
        "parameters": {
            "movie": ("Movie", False), "destinationName": ("Apple TV Name", True),
            "fromBeginning": ("Play from Beginning", False),
        },
        "summary": "Send ${movie} to Apple TV",
        "other_parameters": ["destinationName", "fromBeginning"],
    },
    "AddMovieToPlaylistIntent": {
        "title": "Add Movie to Playlist", "parameters": {"movie": ("Movie", False)},
        "summary": "Add ${movie} to playlist", "other_parameters": [],
    },
    "PauseAirCillerIntent": {"title": "Pause AirCiller", "parameters": {}},
    "ResumeAirCillerIntent": {"title": "Resume AirCiller", "parameters": {}},
    "StopAirCillerIntent": {"title": "Stop AirCiller", "parameters": {}},
}
INTENTS = set(ACTION_CONTRACTS)


def catalog_object(value: object, label: str) -> dict:
    if not isinstance(value, dict):
        raise ValueError(f"Invalid App Intents catalog object: {label}.")
    return value


def validate_localized_title(value: object, expected: str, label: str) -> None:
    title = catalog_object(value, label)
    if title.get("key") != expected or title.get("table") != "Shortcuts":
        raise ValueError(f"Incorrect App Intents title or localization table: {label}.")


def validate_catalog(path: Path) -> None:
    """Check the action contract in Apple's real post-extraction JSON catalog.

    The shape was observed from Xcode 26.6 output. Numeric framework enums and
    effectiveBundleIdentifiers are intentionally not interpreted here; an empty
    bundle list is valid when the actions belong to their containing app.
    """
    catalog = catalog_object(json.loads(path.read_text(encoding="utf-8")), "root")
    actions = catalog_object(catalog.get("actions"), "actions")
    if set(actions) != INTENTS:
        raise ValueError("Apple's catalog does not contain exactly the six AirCiller actions.")
    for identifier, expected in ACTION_CONTRACTS.items():
        action = catalog_object(actions[identifier], identifier)
        if (action.get("identifier") != identifier
                or action.get("fullyQualifiedTypeName") != f"{MODULE_NAME}.{identifier}"):
            raise ValueError(f"Incorrect App Intents action identity: {identifier}.")
        visibility = catalog_object(action.get("visibilityMetadata"), f"{identifier}.visibilityMetadata")
        if (action.get("isDiscoverable") is not True or visibility.get("isDiscoverable") is not True
                or visibility.get("assistantOnly") is not False):
            raise ValueError(f"App Intents action is not discoverable in Shortcuts: {identifier}.")
        if action.get("openAppWhenRun") is not True:
            raise ValueError(f"App Intents action does not open AirCiller in the foreground: {identifier}.")
        validate_localized_title(action.get("title"), expected["title"], identifier)
        parameters = action.get("parameters")
        if not isinstance(parameters, list) or any(not isinstance(item, dict) for item in parameters):
            raise ValueError(f"Invalid App Intents parameter list: {identifier}.")
        parameter_names = [item.get("name") for item in parameters]
        if (any(not isinstance(name, str) for name in parameter_names)
                or len(parameters) != len(expected["parameters"])
                or set(parameter_names) != set(expected["parameters"])):
            raise ValueError(f"Incorrect App Intents parameters: {identifier}.")
        for parameter in parameters:
            name = parameter["name"]
            title, optional = expected["parameters"][name]
            if parameter.get("isOptional") is not optional:
                raise ValueError(f"Incorrect App Intents parameter optionality: {identifier}.{name}.")
            validate_localized_title(parameter.get("title"), title, f"{identifier}.{name}")
        if "summary" in expected:
            configuration = catalog_object(action.get("actionConfiguration"), f"{identifier}.actionConfiguration")
            summary = catalog_object(configuration.get("actionSummary"), f"{identifier}.actionSummary")
            wrapper = catalog_object(summary.get("wrapper"), f"{identifier}.summary.wrapper")
            text = catalog_object(wrapper.get("summaryString"), f"{identifier}.summaryString")
            if (wrapper.get("table") != "Shortcuts"
                    or text.get("formatString") != expected["summary"]
                    or text.get("parameterIdentifiers") != ["movie"]
                    or wrapper.get("otherParameterIdentifiers") != expected["other_parameters"]):
                raise ValueError(f"Incorrect App Intents parameter summary: {identifier}.")


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
    validate_catalog(metadata / "extract.actionsdata")


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

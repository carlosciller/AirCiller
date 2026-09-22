"""Local packaging-contract tests, not Shortcuts discovery acceptance."""

import importlib.util
import json
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "Scripts" / "app_intents_metadata.py"
SPEC = importlib.util.spec_from_file_location("app_intents_metadata", SCRIPT)
metadata = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(metadata)


def synthetic_catalog():
    """Minimal observed catalog shape; never used to package an application."""
    definitions = [
        ("OpenMovieIntent", "Open Movie", [("movie", "Movie", False)], "Open ${movie}", []),
        ("SendMovieToAppleTVIntent", "Send Movie to Apple TV", [
            ("movie", "Movie", False), ("destinationName", "Apple TV Name", True),
            ("fromBeginning", "Play from Beginning", False),
        ], "Send ${movie} to Apple TV", ["destinationName", "fromBeginning"]),
        ("AddMovieToPlaylistIntent", "Add Movie to Playlist", [("movie", "Movie", False)],
         "Add ${movie} to playlist", []),
        ("PauseAirCillerIntent", "Pause AirCiller", [], None, []),
        ("ResumeAirCillerIntent", "Resume AirCiller", [], None, []),
        ("StopAirCillerIntent", "Stop AirCiller", [], None, []),
    ]
    actions = {}
    for identifier, title, parameters, summary, other_parameters in definitions:
        action = {
            "identifier": identifier,
            "fullyQualifiedTypeName": f"AirCiller.{identifier}",
            "isDiscoverable": True, "openAppWhenRun": True,
            "visibilityMetadata": {"isDiscoverable": True, "assistantOnly": False},
            "title": {"key": title, "table": "Shortcuts"},
            "parameters": [
                {"name": name, "isOptional": optional, "title": {"key": key, "table": "Shortcuts"}}
                for name, key, optional in parameters
            ],
            "effectiveBundleIdentifiers": [],
        }
        if summary is not None:
            action["actionConfiguration"] = {"actionSummary": {"wrapper": {
                "table": "Shortcuts", "otherParameterIdentifiers": other_parameters,
                "summaryString": {"formatString": summary, "parameterIdentifiers": ["movie"]},
            }}}
        actions[identifier] = action
    return {"actions": actions, "generator": {"name": "synthetic-test-fixture"}}


class AppIntentsMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="airciller-shortcuts-build-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "Project with spaces" / "ShortcutsIntents.swift"
        self.source.parent.mkdir()
        self.source.write_text("// Synthetic packaging fixture\n", encoding="utf-8")
        self.intermediates = self.root / "metadata"
        self.app = self.root / "AirCiller.staged.app"
        self.contents = self.app / "Contents"
        (self.contents / "Resources").mkdir(parents=True)
        (self.contents / "MacOS").mkdir()
        (self.contents / "MacOS" / "AirCiller").write_bytes(b"fixture binary")
        self.processor = self.root / "appintentsmetadataprocessor"
        self.processor.write_text("fixture tool; never executed", encoding="utf-8")
        self.write_info()
        metadata.prepare(self.source, self.intermediates)
        self.constants = metadata.extraction_paths(self.intermediates)[2]
        self.constants.write_text(json.dumps([
            {"typeName": f"AirCiller.{intent}", "conformances": ["AppIntents.AppIntent"]}
            for intent in metadata.INTENTS
        ]), encoding="utf-8")
        self.catalog_path = self.root / "synthetic.actionsdata"

    def validate_catalog(self, catalog):
        self.catalog_path.write_text(json.dumps(catalog), encoding="utf-8")
        metadata.validate_catalog(self.catalog_path)

    def write_info(self, **overrides):
        info = {"CFBundleIdentifier": "local.carlosciller.AirCiller"}
        info.update(overrides)
        with (self.contents / "Info.plist").open("wb") as stream:
            plistlib.dump(info, stream)

    def extract(self):
        metadata.extract(
            source=self.source, intermediates=self.intermediates, app=self.app,
            processor=self.processor, sdk=self.root / "SDK", toolchain=self.root / "Toolchain",
            xcode_version="SyntheticFixture",
        )

    def write_output(self, command, *, check):
        self.assertTrue(check)
        output = Path(command[command.index("--output") + 1]) / "Metadata.appintents"
        output.mkdir()
        (output / "extract.actionsdata").write_text(json.dumps(synthetic_catalog()), encoding="utf-8")
        (output / "version.json").write_text('{"version":1}', encoding="utf-8")

    def test_prepare_maps_exact_source_and_invalidates_stale_constants(self):
        metadata.prepare(self.source, self.intermediates)
        output_map, protocols, constants = metadata.extraction_paths(self.intermediates)
        self.assertEqual(json.loads(output_map.read_text()), {
            str(self.source.resolve()): {"const-values": str(constants.resolve())},
        })
        self.assertIn("AppIntent", json.loads(protocols.read_text()))
        self.assertFalse(constants.exists())

    def test_command_preserves_paths_and_build_identity(self):
        with patch.object(metadata.subprocess, "run", side_effect=self.write_output) as run:
            self.extract()
        command = run.call_args.args[0]
        self.assertEqual(command[command.index("--module-name") + 1], "AirCiller")
        self.assertEqual(command[command.index("--bundle-identifier") + 1], "local.carlosciller.AirCiller")
        self.assertEqual(command[command.index("--source-files") + 1], str(self.source))
        self.assertEqual(command[command.index("--binary-file") + 1], str(self.contents / "MacOS" / "AirCiller"))
        self.assertIn("--compile-time-extraction", command)
        self.assertEqual(command[command.index("--deployment-target") + 1], "14.0")

    def test_candidate_uses_its_own_bundle_identity(self):
        self.write_info(CFBundleIdentifier="local.carlosciller.AirCiller.PlaybackChecks",
                        ACDevelopmentBuild=True, CFBundleDisplayName="AirCiller Test")
        with patch.object(metadata.subprocess, "run", side_effect=self.write_output) as run:
            self.extract()
        command = run.call_args.args[0]
        self.assertEqual(command[command.index("--bundle-identifier") + 1],
                         "local.carlosciller.AirCiller.PlaybackChecks")

    def test_headless_playback_checks_never_produce_shortcuts(self):
        self.write_info(CFBundleIdentifier="local.carlosciller.AirCiller.PlaybackChecks",
                        ACDevelopmentBuild=True, CFBundleDisplayName="AirCiller Playback Checks")
        with patch.object(metadata.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "only supported"):
                self.extract()
        run.assert_not_called()

    def test_empty_constants_are_rejected_before_processor(self):
        self.constants.write_text("[]", encoding="utf-8")
        with patch.object(metadata.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "no App Intents"):
                self.extract()
        run.assert_not_called()

    def test_success_without_metadata_is_a_failure(self):
        with patch.object(metadata.subprocess, "run"):
            with self.assertRaisesRegex(ValueError, "did not produce"):
                self.extract()

    def test_partial_or_wrong_module_constants_are_rejected(self):
        for values in (
            [{"typeName": "AirCiller.OpenMovieIntent", "conformances": ["AppIntents.AppIntent"]}],
            [{"typeName": f"Wrong.{name}", "conformances": ["AppIntents.AppIntent"]}
             for name in metadata.INTENTS],
        ):
            with self.subTest(values=values):
                self.constants.write_text(json.dumps(values), encoding="utf-8")
                with patch.object(metadata.subprocess, "run") as run:
                    with self.assertRaisesRegex(ValueError, "all six"):
                        self.extract()
                run.assert_not_called()

    def test_processor_failure_is_not_swallowed(self):
        with patch.object(metadata.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "fixture")):
            with self.assertRaises(subprocess.CalledProcessError):
                self.extract()

    def test_stale_metadata_is_rejected(self):
        (self.contents / "Resources" / "Metadata.appintents").mkdir()
        with patch.object(metadata.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "fresh staged bundle"):
                self.extract()
        run.assert_not_called()

    def test_build_cannot_disable_shortcuts_for_the_production_bundle(self):
        result = subprocess.run(
            ["/bin/zsh", str(SCRIPT.parent.parent / "build.sh"), "--without-shortcuts"],
            check=False, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("Usage:", result.stderr)

    def test_catalog_accepts_containing_app_identity_without_effective_bundle_ids(self):
        self.validate_catalog(synthetic_catalog())

    def test_catalog_rejects_missing_and_unexpected_actions(self):
        missing = synthetic_catalog()
        del missing["actions"]["StopAirCillerIntent"]
        extra = synthetic_catalog()
        extra["actions"]["UnexpectedIntent"] = {}
        for catalog in (missing, extra):
            with self.subTest(catalog=catalog):
                with self.assertRaisesRegex(ValueError, "exactly the six"):
                    self.validate_catalog(catalog)

    def test_catalog_rejects_wrong_module_or_identifier(self):
        for field, value in (("fullyQualifiedTypeName", "Other.OpenMovieIntent"), ("identifier", "OtherIntent")):
            with self.subTest(field=field):
                catalog = synthetic_catalog()
                catalog["actions"]["OpenMovieIntent"][field] = value
                with self.assertRaisesRegex(ValueError, "action identity"):
                    self.validate_catalog(catalog)

    def test_catalog_rejects_wrong_title_or_table(self):
        for field, value in (("key", "Unrelated action"), ("table", "Localizable")):
            with self.subTest(field=field):
                catalog = synthetic_catalog()
                catalog["actions"]["PauseAirCillerIntent"]["title"][field] = value
                with self.assertRaisesRegex(ValueError, "title or localization"):
                    self.validate_catalog(catalog)

    def test_catalog_rejects_hidden_assistant_only_or_background_actions(self):
        for variant in ("hidden", "visibility", "assistant_only", "background"):
            with self.subTest(variant=variant):
                catalog = synthetic_catalog()
                action = catalog["actions"]["ResumeAirCillerIntent"]
                if variant == "hidden":
                    action["isDiscoverable"] = False
                elif variant == "visibility":
                    action["visibilityMetadata"]["isDiscoverable"] = False
                elif variant == "assistant_only":
                    action["visibilityMetadata"]["assistantOnly"] = True
                else:
                    action["openAppWhenRun"] = False
                with self.assertRaisesRegex(ValueError, "discoverable|foreground"):
                    self.validate_catalog(catalog)

    def test_catalog_rejects_missing_renamed_and_duplicate_parameters(self):
        for variant in ("missing", "renamed", "duplicate"):
            with self.subTest(variant=variant):
                catalog = synthetic_catalog()
                parameters = catalog["actions"]["SendMovieToAppleTVIntent"]["parameters"]
                if variant == "missing":
                    parameters.pop()
                elif variant == "renamed":
                    parameters[1]["name"] = "receiverAddress"
                else:
                    parameters[1] = dict(parameters[0])
                with self.assertRaisesRegex(ValueError, "parameters"):
                    self.validate_catalog(catalog)

    def test_catalog_rejects_wrong_parameter_optionality_or_localization(self):
        for variant in ("required_destination", "optional_movie", "title", "table"):
            with self.subTest(variant=variant):
                catalog = synthetic_catalog()
                parameters = catalog["actions"]["SendMovieToAppleTVIntent"]["parameters"]
                if variant == "required_destination":
                    parameters[1]["isOptional"] = False
                elif variant == "optional_movie":
                    parameters[0]["isOptional"] = True
                else:
                    parameters[0]["title"]["key" if variant == "title" else "table"] = "Wrong"
                with self.assertRaisesRegex(ValueError, "optionality|localization"):
                    self.validate_catalog(catalog)

    def test_catalog_rejects_wrong_summary_text_parameters_and_table(self):
        for variant in ("text", "parameters", "other_parameters", "table"):
            with self.subTest(variant=variant):
                catalog = synthetic_catalog()
                wrapper = catalog["actions"]["SendMovieToAppleTVIntent"]["actionConfiguration"]["actionSummary"]["wrapper"]
                if variant == "text":
                    wrapper["summaryString"]["formatString"] = "Send another movie"
                elif variant == "parameters":
                    wrapper["summaryString"]["parameterIdentifiers"] = []
                elif variant == "other_parameters":
                    wrapper["otherParameterIdentifiers"] = ["destinationName"]
                else:
                    wrapper["table"] = "Localizable"
                with self.assertRaisesRegex(ValueError, "parameter summary"):
                    self.validate_catalog(catalog)

    def test_catalog_rejects_malformed_shapes_as_validation_errors(self):
        for variant in ("root", "actions", "action", "title", "parameters", "parameter_name", "summary"):
            with self.subTest(variant=variant):
                catalog = synthetic_catalog()
                action = catalog["actions"]["OpenMovieIntent"]
                if variant == "root":
                    catalog = []
                elif variant == "actions":
                    catalog["actions"] = []
                elif variant == "action":
                    catalog["actions"]["OpenMovieIntent"] = None
                elif variant == "title":
                    action["title"] = "Open Movie"
                elif variant == "parameters":
                    action["parameters"] = [None]
                elif variant == "parameter_name":
                    action["parameters"][0]["name"] = []
                else:
                    action["actionConfiguration"]["actionSummary"] = None
                with self.assertRaises(ValueError):
                    self.validate_catalog(catalog)

    def test_post_extraction_missing_action_fails_even_with_complete_swift_constants(self):
        def missing_action(command, *, check):
            self.write_output(command, check=check)
            path = self.contents / "Resources" / "Metadata.appintents" / "extract.actionsdata"
            catalog = json.loads(path.read_text(encoding="utf-8"))
            del catalog["actions"]["StopAirCillerIntent"]
            path.write_text(json.dumps(catalog), encoding="utf-8")

        with patch.object(metadata.subprocess, "run", side_effect=missing_action):
            with self.assertRaisesRegex(ValueError, "exactly the six"):
                self.extract()


if __name__ == "__main__":
    unittest.main()

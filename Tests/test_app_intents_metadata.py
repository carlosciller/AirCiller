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
        (output / "extract.actionsdata").write_bytes(b"synthetic contract fixture")
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


if __name__ == "__main__":
    unittest.main()

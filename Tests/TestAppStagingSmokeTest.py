import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Scripts"))
import stage_test_app as staging


class StagingTests(unittest.TestCase):
    def test_reuse_replacement_and_identity_rejection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Source.app"
            source.mkdir()
            (source / "version").write_text("one")
            destination = root / "Tests"
            def identity(app):
                return (app.joinpath("version").read_text(), "stable certificate requirement")
            with patch.object(staging, "verified_identity", side_effect=identity), patch.object(
                staging.subprocess, "run", return_value=SimpleNamespace(stdout="")):
                binary = staging.stage(source, destination)
                self.assertEqual(binary, destination / "AirCiller Test.app/Contents/MacOS/AirCiller")
                self.assertEqual(staging.stage(source, destination), binary)
                (source / "version").write_text("two")
                staging.stage(source, destination)
                self.assertEqual((destination / "AirCiller Test.app/version").read_text(), "two")
                self.assertFalse((destination / "AirCiller Test.previous.app").exists())
            with patch.object(staging, "verified_identity", side_effect=[("three", "new"), ("two", "old")]):
                with self.assertRaisesRegex(ValueError, "identity changed"):
                    staging.stage(source, destination)
            self.assertEqual((destination / "AirCiller Test.app/version").read_text(), "two")

    def test_unsigned_rejected_before_copy(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "Source.app"
            source.mkdir()
            with patch.object(staging, "verified_identity", side_effect=ValueError("unsigned")):
                with self.assertRaises(ValueError):
                    staging.stage(source, Path(directory) / "Tests")
            self.assertFalse((Path(directory) / "Tests/AirCiller Test.app").exists())

    def test_running_app_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Source.app"
            source.mkdir()
            target = root / "Tests/AirCiller Test.app"
            target.mkdir(parents=True)
            (target / "preserve").write_text("running")
            with patch.object(staging, "verified_identity", side_effect=[("new", "same"), ("old", "same")]), \
                    patch.object(staging.subprocess, "run", return_value=SimpleNamespace(
                        stdout=str(target / "Contents/MacOS/AirCiller") + "\n")):
                with self.assertRaisesRegex(ValueError, "running"):
                    staging.stage(source, target.parent)
            self.assertEqual((target / "preserve").read_text(), "running")

    def test_partial_copy_does_not_replace_current_app(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Source.app"
            source.mkdir()
            target = root / "Tests/AirCiller Test.app"
            target.mkdir(parents=True)
            (target / "preserve").write_text("old")
            with patch.object(staging, "verified_identity", side_effect=[
                ("new", "same"), ("old", "same"), ValueError("bad copy")
            ]), patch.object(staging.subprocess, "run", return_value=SimpleNamespace(stdout="")):
                with self.assertRaisesRegex(ValueError, "bad copy"):
                    staging.stage(source, target.parent)
            self.assertEqual((target / "preserve").read_text(), "old")

    def test_destination_symlink_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            elsewhere = root / "Elsewhere"
            elsewhere.mkdir()
            target = root / "Tests"
            target.symlink_to(elsewhere, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "symlink"):
                staging.stage(root, target)
            self.assertEqual(list(elsewhere.iterdir()), [])


if __name__ == "__main__":
    unittest.main()

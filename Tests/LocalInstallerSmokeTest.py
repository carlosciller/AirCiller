"""Local installer path protection, with isolated fake bundles and signing only."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="airciller-install-fixture-")
        self.root = Path(self.temporary.name).resolve()
        self.project = self.root / "project"
        self.script = self.project / "Scripts/install_local.sh"
        self.script.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / "Scripts/install_local.sh", self.script)
        self.source = self.project / ".build/AirCiller.app"
        self.bundle(self.source, "new")
        self.destination = self.root / "destination"
        self.destination.mkdir()
        self.target = self.destination / "AirCiller.app"
        self.bundle(self.target, "old")
        self.rollback = self.destination / "AirCiller.rollback.app"
        self.bundle(self.rollback, "recovery")
        self.stage = self.destination / ".AirCiller.installing.app"
        self.bundle(self.stage, "abandoned-stage")
        # Never inspect running user apps or sign fixtures. Copies/moves use the
        # real tools, exclusively within this uniquely-created temporary tree.
        stub = self.root / "tools"
        stub.mkdir()
        for name, result in [("pgrep", 1), ("codesign", 0)]:
            path = stub / name
            path.write_text(f"#!/bin/sh\nexit {result}\n")
            path.chmod(0o700)
        self.environment = dict(os.environ, PATH=f"{stub}:/usr/bin:/bin:/usr/sbin:/sbin")

    def tearDown(self):
        self.temporary.cleanup()

    def bundle(self, path, marker, identifier="local.carlosciller.AirCiller"):
        contents = path / "Contents"
        contents.mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": identifier}))
        (contents / "fixture.txt").write_text(marker)

    def run_installer(self, target):
        return subprocess.run(["/bin/zsh", str(self.script), str(target)],
                              env=self.environment, capture_output=True, text=True, timeout=10)

    def snapshot(self):
        return sorted((str(path.relative_to(self.root)),
                       "link:" + os.readlink(path) if path.is_symlink() else path.read_bytes())
                      for path in self.root.rglob("*") if path.is_file() or path.is_symlink())

    def assert_rejected_unchanged(self, target):
        before = self.snapshot()
        result = self.run_installer(target)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.snapshot(), before)

    def test_rejects_wrong_directory_names_and_internal_collisions(self):
        for target in [self.destination, self.rollback, self.stage, self.source]:
            with self.subTest(target=target.name):
                self.assert_rejected_unchanged(target)

    def test_rejects_unrelated_target_bundle(self):
        (self.target / "Contents/Info.plist").write_bytes(
            plistlib.dumps({"CFBundleIdentifier": "example.other-app"}))
        self.assert_rejected_unchanged(self.target)

    def test_rejects_unrelated_rollback_before_removing_staging(self):
        (self.rollback / "Contents/Info.plist").unlink()
        self.assert_rejected_unchanged(self.target)

    def test_rejects_target_staging_and_rollback_symlinks(self):
        for path in [self.target, self.stage, self.rollback]:
            with self.subTest(path=path.name):
                saved = path.with_suffix(".saved")
                path.rename(saved)
                path.symlink_to(saved, target_is_directory=True)
                self.assert_rejected_unchanged(self.target)
                path.unlink()
                saved.rename(path)

    def test_installs_and_preserves_the_previous_app(self):
        result = self.run_installer(self.target)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.target / "Contents/fixture.txt").read_text(), "new")
        self.assertEqual((self.rollback / "Contents/fixture.txt").read_text(), "old")
        self.assertEqual((self.source / "Contents/fixture.txt").read_text(), "new")
        self.assertFalse(self.stage.exists())


if __name__ == "__main__":
    unittest.main()

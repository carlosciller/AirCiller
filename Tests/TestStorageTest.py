"""Retention safety tests: disposable local files only, no media devices."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location(
    "test_storage", Path(__file__).resolve().parents[1] / "Scripts/test_storage.py")
storage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(storage)


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.project = Path(self.temporary.name)
        self.build = storage.build_directory(self.project)

    def run_directory(self, name="run.synthetic"):
        run = self.build / "startup-benchmark" / name
        run.mkdir(parents=True)
        return run

    def test_finished_run_keeps_reports_and_removes_only_generated_payload(self):
        run = self.run_directory()
        expected = {"report.json": b'{"outcome":"failed"}', "frame.png": b"image",
                    "input.swift": b"source", "subtitle.vtt": b"WEBVTT"}
        for name, data in expected.items():
            (run / name).write_bytes(data)
        (run / "fixture.mkv").write_bytes(b"synthetic")
        (run / "benchmark").write_bytes(b"\xcf\xfa\xed\xfe" + b"binary")
        (run / "benchmark").chmod(0o700)
        with mock.patch.dict(os.environ, {"AIRCILLER_TEST_STORAGE_OWNER": "owner"}):
            storage.register_run(self.project, run)
        state = json.loads((run / storage.MARKER).read_text())
        state.update(status="complete", exitCode=1)
        storage.write_marker(run, state)
        storage.preflight(self.build)
        storage.preflight(self.build)  # Idempotent.
        self.assertFalse((run / "fixture.mkv").exists())
        self.assertFalse((run / "benchmark").exists())
        for name, data in expected.items():
            self.assertEqual((run / name).read_bytes(), data)
        self.assertEqual(json.loads((run / storage.MARKER).read_text())["exitCode"], 1)

    def test_active_and_unregistered_runs_and_protected_paths_are_untouched(self):
        for name in ("run.active", "run.unregistered"):
            run = self.run_directory(name)
            (run / "fixture.mkv").write_bytes(b"keep")
            if name == "run.active":
                storage.write_marker(run, {"schema": 1, "status": "active"})
        protected = [self.project / "film.mkv", self.build / "dependencies/engine.mkv",
                     self.build / "rollback-0.17.1-to-0.17.3/AirCiller.app/binary",
                     self.build / "retained-reports-20261019/reports.tar.gz"]
        for path in protected:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"keep")
        storage.preflight(self.build)
        for path in protected:
            self.assertEqual(path.read_bytes(), b"keep")
        for run in storage.runs(self.build):
            self.assertEqual((run / "fixture.mkv").read_bytes(), b"keep")

    def test_symlinks_cannot_reach_originals(self):
        original = self.project / "original.mkv"
        original.write_bytes(b"private")
        run = self.run_directory()
        (run / "linked.mkv").symlink_to(original)
        (run / "outside").symlink_to(self.project, target_is_directory=True)
        storage.write_marker(run, {"schema": 1, "status": "complete"})
        storage.preflight(self.build)
        self.assertEqual(original.read_bytes(), b"private")
        (self.build / "performance").symlink_to(self.project, target_is_directory=True)
        self.assertEqual(list(storage.runs(self.build)), [run])

    def test_build_symlink_is_rejected(self):
        self.build.rmdir()
        self.build.symlink_to(self.project, target_is_directory=True)
        with self.assertRaises(ValueError):
            storage.build_directory(self.project)

    def test_limit_blocks_action_without_deleting_reports(self):
        report = self.build / "report.json"
        report.write_bytes(b"report")
        action = mock.Mock()
        with self.assertRaisesRegex(ValueError, "No new test was started"):
            storage.guarded(self.project, action, limit=1)
        action.assert_not_called()
        self.assertEqual(report.read_bytes(), b"report")

    def test_failed_action_is_cleaned_but_concurrent_unowned_run_is_not(self):
        def action():
            owned = self.run_directory("run.owned")
            storage.register_run(self.project, owned)
            (owned / "fixture.mkv").write_bytes(b"generated")
            other = self.run_directory("run.other")
            (other / "fixture.mkv").write_bytes(b"other")
            raise RuntimeError("test failure")
        with self.assertRaisesRegex(RuntimeError, "test failure"):
            storage.guarded(self.project, action)
        self.assertFalse((self.build / "startup-benchmark/run.owned/fixture.mkv").exists())
        self.assertTrue((self.build / "startup-benchmark/run.other/fixture.mkv").exists())

    def test_concurrent_guard_is_rejected(self):
        def action():
            with self.assertRaisesRegex(ValueError, "Another guarded test"):
                storage.guarded(self.project, mock.Mock())
            return 0
        self.assertEqual(storage.guarded(self.project, action), 0)


if __name__ == "__main__":
    unittest.main()

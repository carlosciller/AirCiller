"""Exercise watchdog and shutdown with disposable processes, never a receiver."""

import importlib.util
from pathlib import Path
import sys
import time
import unittest
from unittest import mock
import contextlib
import io

spec = importlib.util.spec_from_file_location(
    "playback_checks", Path(__file__).resolve().parents[1] / "Scripts/playback_checks.py"
)
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


class LauncherTests(unittest.TestCase):
    def test_local_only_rejects_capture_and_tv_flags_without_starting_processes(self):
        for extra in ("--capture", "--prepare", "--tv-is-idle"):
            with mock.patch.object(sys, "argv", ["playback_checks.py", "unused.json", "--local-only", extra]), \
                    mock.patch.object(launcher, "run_process") as run, contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit): launcher.main()
                run.assert_not_called()

    def test_normal_exit(self):
        self.assertIsNone(launcher.run_process([sys.executable, "-c", "pass"], timeout=2))

    def test_failed_exit(self):
        self.assertEqual(
            launcher.run_process([sys.executable, "-c", "raise SystemExit(3)"], timeout=2), "checkAppFailed"
        )

    def test_watchdog(self):
        began = time.monotonic()
        self.assertEqual(
            launcher.run_process([sys.executable, "-c", "import time; time.sleep(30)"], timeout=0.15),
            "watchdogTimeout",
        )
        self.assertLess(time.monotonic() - began, 10)

    def test_surviving_helper_is_not_success(self):
        # The short-lived parent exits successfully while its child keeps the group alive.
        source = "import subprocess,sys; subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)'])"
        self.assertEqual(launcher.run_process([sys.executable, "-c", source], timeout=2), "leftoverProcesses")


if __name__ == "__main__":
    unittest.main()

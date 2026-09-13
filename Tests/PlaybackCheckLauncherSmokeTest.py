"""Exercise watchdog and shutdown with disposable processes, never a receiver."""

import importlib.util
from pathlib import Path
import sys
import time
import unittest
from unittest import mock
import contextlib
import io
import subprocess

spec = importlib.util.spec_from_file_location(
    "playback_checks", Path(__file__).resolve().parents[1] / "Scripts/playback_checks.py"
)
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


class LauncherTests(unittest.TestCase):
    def fake_process(self):
        process = mock.Mock(pid=424242, returncode=0)
        process.poll.return_value = 0
        process.wait.return_value = 0
        return process

    def test_initial_permission_race_is_rechecked_and_child_reaped(self):
        process = self.fake_process()
        with mock.patch.object(launcher.os, "killpg", side_effect=[
                PermissionError(), PermissionError(), ProcessLookupError()]) as kill:
            self.assertFalse(launcher.finish_process_group(process))
        process.wait.assert_called_once_with(timeout=3)
        self.assertEqual([call.args for call in kill.call_args_list], [
            (process.pid, 0), (process.pid, launcher.signal.SIGTERM), (process.pid, 0)])

    def test_persistent_permission_failure_is_not_cleanup_success(self):
        process = self.fake_process()
        clock = [0.0]
        def advance(seconds):
            clock[0] += seconds
        original = RuntimeError("processOutputLimit")
        with mock.patch.object(launcher.os, "killpg", side_effect=PermissionError()) as kill, \
                mock.patch.object(launcher.time, "monotonic", side_effect=lambda: clock[0]), \
                mock.patch.object(launcher.time, "sleep", side_effect=advance):
            with self.assertRaisesRegex(OSError, "cleanupUnverified.*processOutputLimit") as failure:
                try:
                    raise original
                finally:
                    launcher.finish_process_group(process)
        self.assertIs(failure.exception.__cause__, original)
        process.wait.assert_called_once_with(timeout=3)
        self.assertTrue(all(call.args[0] == process.pid for call in kill.call_args_list))
        self.assertLessEqual(clock[0], 6.2)

    def test_group_disappears_between_probe_and_signal(self):
        process = self.fake_process()
        with mock.patch.object(launcher.os, "killpg", side_effect=[
                None, ProcessLookupError(), ProcessLookupError()]):
            self.assertTrue(launcher.finish_process_group(process))
        process.wait.assert_called_once_with(timeout=3)

    def test_initial_missing_group_still_reaps_direct_child(self):
        process = self.fake_process()
        with mock.patch.object(launcher.os, "killpg", side_effect=ProcessLookupError()):
            self.assertFalse(launcher.finish_process_group(process))
        process.wait.assert_called_once_with(timeout=3)

    def test_real_child_is_reaped_after_initial_permission_error(self):
        process = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"], start_new_session=True)
        real_killpg = launcher.os.killpg
        first = [True]
        def permission_once(pid, number):
            if first[0] and number == 0:
                first[0] = False
                raise PermissionError()
            return real_killpg(pid, number)
        try:
            with mock.patch.object(launcher.os, "killpg", side_effect=permission_once):
                self.assertTrue(launcher.finish_process_group(process))
            self.assertIsNotNone(process.returncode)
            self.assertEqual(process.wait(timeout=.1), process.returncode)
        finally:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=3)

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

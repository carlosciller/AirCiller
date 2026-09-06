"""Capture orchestration tests with fake processes. No media device is opened."""
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Scripts"))
import playback_capture as capture


class CaptureWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="airciller-capture-test-")
        self.root = Path(self.temporary.name)
        self.fixture = self.root / "sample.mp4"
        self.fixture.write_bytes(b"fixture")
        self.config = {"version": 1, "deviceID": "test-receiver", "cases": ["directHDR"],
                       "captureSource": {"uniqueID": "approved-screen", "name": "Test receiver", "approvedAppleTV": True},
                       "hdrFixture": str(self.fixture)}

    def tearDown(self):
        self.temporary.cleanup()

    def test_validation_opens_no_process(self):
        config_path = self.root / "config.json"
        capture.save_json(config_path, self.config)
        with mock.patch.object(capture, "start_process", side_effect=AssertionError("No device or process")):
            self.assertEqual(capture.run_workflow(config_path, self.root), 0)

    def test_documented_command_leaves_source_clean(self):
        scripts = self.root / "Scripts"
        scripts.mkdir()
        for name in ("playback_checks.py", "playback_capture.py"):
            shutil.copyfile(Path(capture.__file__).parent / name, scripts / name)
        config_path = self.root / "config.json"
        capture.save_json(config_path, self.config)
        environment = dict(os.environ)
        for name in ("PYTHONPYCACHEPREFIX", "PYTHONDONTWRITEBYTECODE"):
            environment.pop(name, None)
        result = subprocess.run([sys.executable, scripts / "playback_checks.py", config_path, "--capture"],
                                env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((scripts / "__pycache__").exists())

    def test_configuration_rejections(self):
        changes = [{"version": True}, {"deviceID": ""}, {"cases": []}, {"cases": ["hlsNoSubtitles", "hlsNoSubtitles"]},
                   {"cases": ["camera"]}, {"hdrFixture": "relative.mp4"}, {"extra": "ignored typo"},
                   {"captureSource": {"uniqueID": "screen", "name": "Test", "approvedAppleTV": False}},
                   {"captureSource": {"uniqueID": "screen\nother", "name": "Test", "approvedAppleTV": True}}]
        for change in changes:
            with self.subTest(change=change), self.assertRaises(capture.CaptureError):
                capture.validate_config(dict(self.config, **change))

    def test_reports_do_not_overwrite(self):
        target = self.root / "report.json"
        capture.save_json(target, {"first": True})
        with self.assertRaises(FileExistsError):
            capture.save_json(target, {"first": False})
        self.assertEqual(json.loads(target.read_text()), {"first": True})

    def test_bounded_process_and_timeout(self):
        self.assertEqual(capture.bounded_command([sys.executable, "-c", "print('ok')"]), b"ok\n")
        with self.assertRaisesRegex(capture.CaptureError, "processOutputLimit"):
            capture.bounded_command([sys.executable, "-c", "print('x'*5000)"], limit=100)
        with self.assertRaisesRegex(capture.CaptureError, "processTimeout"):
            capture.bounded_command([sys.executable, "-c", "import time; time.sleep(20)"], timeout=0.1)

    def commands(self, capture_body=None, app_body=None):
        ready, stop = self.root / "capture.ready", self.root / "capture.stop"
        completed = self.root / "completed"
        app_body = app_body or (
            "import pathlib,sys,time; ready=pathlib.Path(sys.argv[1]); "
            "print('Checking: awaiting_capture_ready', flush=True)\n"
            "while not ready.exists(): time.sleep(.01)\n"
            "time.sleep(.15)\npathlib.Path(sys.argv[2]).touch()\n")
        capture_body = capture_body or (
            "import pathlib,sys,time; pathlib.Path(sys.argv[1]).touch(); stop=pathlib.Path(sys.argv[2])\n"
            "while not stop.exists(): time.sleep(.01)\n")
        return ([sys.executable, "-u", "-c", app_body, str(ready), str(completed)],
                [sys.executable, "-u", "-c", capture_body, str(ready), str(stop)], ready, stop, completed)

    def test_gate_and_orderly_cleanup(self):
        app, sampler, ready, stop, completed = self.commands()
        capture.supervise_case(app, sampler, ready, stop, timeout=3)
        self.assertTrue(completed.exists())
        self.assertTrue(stop.exists())

    def test_blocked_app_never_starts_capture(self):
        app, sampler, ready, stop, completed = self.commands(app_body="raise SystemExit(1)")
        with self.assertRaisesRegex(capture.CaptureError, "controlsBlockedBeforeCapture"):
            capture.supervise_case(app, sampler, ready, stop, timeout=3)
        self.assertFalse(ready.exists())

    def test_lost_capture_terminates_waiting_app(self):
        app, sampler, ready, stop, completed = self.commands(capture_body="raise SystemExit(1)")
        with self.assertRaisesRegex(capture.CaptureError, "captureLost"):
            capture.supervise_case(app, sampler, ready, stop, timeout=3)
        self.assertFalse(completed.exists())

    def test_capture_without_ready_is_bounded(self):
        app, sampler, ready, stop, completed = self.commands(capture_body="import time; time.sleep(20)")
        began = time.monotonic()
        with self.assertRaisesRegex(capture.CaptureError, "captureNotReady"):
            capture.supervise_case(app, sampler, ready, stop, timeout=3, ready_timeout=.1)
        self.assertLess(time.monotonic() - began, 5)
        self.assertFalse(completed.exists())

    def evidence(self, case="hlsSubtitles"):
        rows, frames = [], []
        for index in range(18):
            uptime = 102 + index * .5
            name = f"frame-{index + 1:03d}.png"
            rows.extend([{"kind": "video", "uptime": uptime, "frame": name},
                         {"kind": "audio", "uptime": uptime, "rmsDBFS": -25}])
            frames.append({"frame": name, "anyCue": case != "hlsNoSubtitles", "expectedCue": case != "hlsNoSubtitles",
                           "centralDifference": 5, "testPattern": True})
        samples = {"schemaVersion": 1, "sourceVerified": True, "complete": True, "rows": rows}
        control = {"outcome": capture.CONTROL_PASS, "results": [{"cleanupConfirmed": True,
            "route": "directHDR" if case == "directHDR" else "hls", "subtitlesRequested": case != "hlsNoSubtitles",
            "startedAtUptime": 100, "elapsedSeconds": 11, "events": [{"kind": "playing", "origin": "receiver", "seconds": 1}]}]}
        return samples, frames, control

    def test_evidence_for_each_case(self):
        for case in capture.BASIC_CASES:
            result = capture.assess_samples(*self.evidence(case), case)
            self.assertEqual(result["outcome"], capture.OUTPUT_PASS)

    def test_missing_or_misleading_evidence(self):
        samples, frames, control = self.evidence()
        changes = [
            lambda s, f, c: s.update(sourceVerified=False),
            lambda s, f, c: s.update(schemaVersion=True),
            lambda s, f, c: s.update(complete=False),
            lambda s, f, c: c.update(outcome="inconclusive"),
            lambda s, f, c: c["results"][0].update(startedAtUptime=float("nan")),
            lambda s, f, c: c["results"][0].update(route="directHDR"),
            lambda s, f, c: s.update(rows=s["rows"][:12]),
            lambda s, f, c: f.append(f[0]),
            lambda s, f, c: f.append(None),
            lambda s, f, c: s["rows"].append(None),
            lambda s, f, c: c["results"][0].update(events=[None]),
            lambda s, f, c: f[0].update(centralDifference=float("nan")),
        ]
        for change in changes:
            s, f, c = copy.deepcopy((samples, frames, control))
            change(s, f, c)
            with self.assertRaises(capture.CaptureError):
                capture.assess_samples(s, f, c, "hlsSubtitles")
        for field, value, gap in [("expectedCue", False, "expectedSubtitleCueNotObserved"),
                                  ("centralDifference", 0, "movingPictureNotObserved"),
                                  ("testPattern", False, "expectedPictureNotObserved")]:
            f = [dict(row, **{field: value}) for row in frames]
            self.assertIn(gap, capture.assess_samples(samples, f, control, "hlsSubtitles")["gaps"])

    def test_malformed_evidence_is_not_accepted(self):
        samples, frames, control = self.evidence()
        for evidence in [(None, frames, control), (samples, None, control), (samples, frames, None)]:
            with self.assertRaises(capture.CaptureError):
                capture.assess_samples(*evidence, "hlsSubtitles")

    def test_silence_is_not_audio_success(self):
        samples, frames, control = self.evidence()
        for row in samples["rows"]:
            if row["kind"] == "audio": row["rmsDBFS"] = -160
        self.assertIn("audioNotObserved", capture.assess_samples(samples, frames, control, "hlsSubtitles")["gaps"])

    def test_stale_subtitles_fail_no_subtitle_case(self):
        samples, frames, control = self.evidence("hlsNoSubtitles")
        frames[4]["anyCue"] = True
        self.assertIn("unexpectedSubtitles", capture.assess_samples(samples, frames, control, "hlsNoSubtitles")["gaps"])


if __name__ == "__main__":
    unittest.main()

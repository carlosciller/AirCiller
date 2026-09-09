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

    def preflight_command(self, rows=None, body=None):
        directory = self.root / "preflight"
        directory.mkdir()
        (directory / "capture").mkdir()
        rows = [{"kind": "video", "frame": "frame-001.png"}] if rows is None else rows
        code = (
            "import json, pathlib, sys, time\n"
            "root = pathlib.Path(sys.argv[1])\n"
            "(root / 'capture.ready').touch()\n"
            "while not (root / 'capture.stop').exists(): time.sleep(.01)\n"
            f"samples = {{'schemaVersion': 1, 'sourceVerified': True, 'complete': True, 'rows': {rows!r}}}\n"
            "(root / 'capture' / 'samples.json').write_text(json.dumps(samples))\n"
        ) if body is None else body
        return [sys.executable, "-c", code, directory], directory

    def test_preflight_accepts_initial_frame_without_claiming_audio_or_playback(self):
        command, directory = self.preflight_command()
        result = capture.preflight_capture(command, directory, ready_timeout=2)
        self.assertEqual(result["outcome"], "initial_frame_received")
        self.assertEqual(result["videoSamples"], 1)
        self.assertEqual(result["audioSamples"], 0)
        self.assertTrue((directory / "capture.stop").exists())

    def test_preflight_no_frame_is_bounded_and_reaps_process(self):
        command, directory = self.preflight_command(body="import time; time.sleep(20)")
        launched = []
        start = capture.start_process
        def track(*args, **kwargs):
            value = start(*args, **kwargs)
            launched.append(value[0])
            return value
        began = time.monotonic()
        with mock.patch.object(capture, "start_process", side_effect=track):
            with self.assertRaisesRegex(capture.CaptureError, "captureNoInitialFrame"):
                capture.preflight_capture(command, directory, ready_timeout=.1)
        self.assertLess(time.monotonic() - began, 5)
        self.assertIsNotNone(launched[0].poll())

    def test_preflight_ready_marker_without_frame_does_not_pass(self):
        command, directory = self.preflight_command(rows=[])
        with self.assertRaisesRegex(capture.CaptureError, "captureNoInitialFrame"):
            capture.preflight_capture(command, directory, ready_timeout=2)

    def test_preflight_no_frame_requests_orderly_session_shutdown(self):
        command, directory = self.preflight_command(body=(
            "import pathlib, sys, time\n"
            "root = pathlib.Path(sys.argv[1])\n"
            "print('captureRunning', flush=True)\n"
            "while not (root / 'capture.stop').exists(): time.sleep(.01)\n"
            "print('captureStopping', flush=True)\n"
            "(root / 'orderly-stop').touch()\n"
            "raise SystemExit(10)\n"))
        with self.assertRaisesRegex(capture.CaptureError, "captureNoInitialFrame"):
            capture.preflight_capture(command, directory, ready_timeout=.2)
        self.assertTrue((directory / "orderly-stop").exists())
        diagnostic = json.loads((directory / "startup-diagnostic.json").read_text())
        self.assertEqual(diagnostic["processExitCode"], 10)
        self.assertEqual(diagnostic["stages"], ["captureRunning", "captureStopping"])

    def test_preflight_failed_source_does_not_pass(self):
        command, directory = self.preflight_command(body="raise SystemExit(5)")
        with self.assertRaisesRegex(capture.CaptureError, "captureReadinessFailed"):
            capture.preflight_capture(command, directory, ready_timeout=2)

    def test_startup_diagnostic_retains_only_allowed_stages(self):
        command, directory = self.preflight_command(body=(
            "print('captureSourceVerified', flush=True)\n"
            "print('private-device-label-must-not-be-recorded', flush=True)\n"
            "print('captureStarting', flush=True)\n"
            "raise SystemExit(6)\n"))
        with self.assertRaisesRegex(capture.CaptureError, "captureReadinessFailed"):
            capture.preflight_capture(command, directory, ready_timeout=2)
        diagnostic = json.loads((directory / "startup-diagnostic.json").read_text())
        self.assertEqual(diagnostic["stages"], ["captureSourceVerified", "captureStarting"])
        self.assertEqual(diagnostic["processExitCode"], 6)
        self.assertFalse(diagnostic["readyMarkerObserved"])
        self.assertNotIn("private-device-label", json.dumps(diagnostic))
        self.assertIn("output directory", capture.capture_readiness_guidance(diagnostic))

    def test_guidance_distinguishes_startup_from_no_frames(self):
        self.assertIn("did not finish starting", capture.capture_readiness_guidance({"stages": ["captureStarting"]}))
        self.assertIn("no usable initial frame", capture.capture_readiness_guidance({"stages": ["captureStarting", "captureRunning"]}))

    def test_enablement_diagnostic_filters_payload_and_preserves_status(self):
        output = mock.Mock()
        output.snapshot.return_value = (
            b"captureEnablementFailed private-device 268435459\n"
            b"captureEnablementFailed wireless 9999999999999999\n"
            b"captureEnablementFailed wireless 2147483648\n"
            b"captureEnablementFailed wireless 268435459 private\n"
            b"captureEnablementFailed wireless 268435459\n")
        diagnostic = capture.capture_startup_diagnostic(output, mock.Mock(returncode=4), self.root / "absent")
        self.assertEqual(diagnostic["enablementFailure"], {"property": "wireless", "status": 268435459})
        self.assertNotIn("private", json.dumps(diagnostic))
        guidance = capture.capture_readiness_guidance(diagnostic)
        self.assertIn("invalid IPC destination", guidance)
        self.assertIn("source was not opened", guidance)
        self.assertNotIn("television and Apple TV are awake", guidance)
        self.assertIn("could not enable screen sources", capture.capture_readiness_guidance({"processExitCode": 4}))

    def workflow_files(self, cases=None):
        binary = self.root / ".build/AirCiller Playback Checks.app/Contents/MacOS/AirCiller"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"fake-app")
        tools = self.root / ".build/playback-capture-tools"
        tools.mkdir()
        for name in ("capture-samples", "analyze-frames"):
            (tools / name).write_bytes(b"fake-tool")
        config_path = self.root / "config.json"
        config = dict(self.config)
        if cases is not None:
            config.update(cases=cases, fixtureEncoder=sys.executable)
        capture.save_json(config_path, config)
        return config_path

    def test_failed_readiness_prevents_credentials_preparation_and_playback(self):
        config_path = self.workflow_files()
        with mock.patch.object(capture, "bounded_command", return_value=b"") as command, \
                mock.patch.object(capture, "preflight_capture", side_effect=capture.CaptureError("captureNoInitialFrame")), \
                mock.patch.object(capture, "prepare_fixtures") as prepare, \
                mock.patch.object(capture, "run_case") as run:
            self.assertEqual(capture.run_workflow(config_path, self.root, run=True), 1)
            prepare.assert_not_called()
            run.assert_not_called()
            self.assertFalse(any("--check-keychain" in call.args[0] for call in command.call_args_list))
        reports = list((self.root / ".build/playback-checks").glob("*/report.json"))
        self.assertEqual(len(reports), 1)
        report = json.loads(reports[0].read_text())
        self.assertEqual(report["outcome"], "blocked")
        self.assertEqual(report["cases"], [])
        self.assertIn("No fixture preparation or playback", report["guidance"])

    def test_successful_readiness_precedes_credentials_and_preparation(self):
        config_path = self.workflow_files()
        events = []
        def command(args, **kwargs):
            self.assertNotIn("--inspect-source", args, "Preflight already checks identity before opening")
            if "--check-keychain" in args: events.append("credentials")
            return b""
        def ready(*args, **kwargs):
            events.append("frame")
            return {"outcome": "initial_frame_received"}
        def prepare(*args, **kwargs):
            events.append("fixtures")
            return {"directHDR": (self.fixture, {})}
        with mock.patch.object(capture, "bounded_command", side_effect=command), \
                mock.patch.object(capture, "preflight_capture", side_effect=ready), \
                mock.patch.object(capture, "prepare_fixtures", side_effect=prepare), \
                mock.patch.object(capture, "run_case", return_value={"outcome": capture.OUTPUT_PASS}):
            self.assertEqual(capture.run_workflow(config_path, self.root, run=True), 0)
        self.assertEqual(events, ["frame", "credentials", "fixtures"])

    def test_cancellation_only_workflow_does_not_capture(self):
        config_path = self.workflow_files(["cancelPreparation"])
        with mock.patch.object(capture, "bounded_command", return_value=b"") as command, \
                mock.patch.object(capture, "preflight_capture") as preflight, \
                mock.patch.object(capture, "prepare_fixtures", return_value={}), \
                mock.patch("playback_scenarios.run_scenario", return_value={"outcome": capture.CANCELLATION_PASS}):
            self.assertEqual(capture.run_workflow(config_path, self.root, run=True), 0)
            preflight.assert_not_called()
            self.assertEqual(sum("--inspect-source" in call.args[0] for call in command.call_args_list), 1)

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

    def test_hdr_hls_requires_its_route_pattern_and_no_subtitles(self):
        samples, frames, control = self.evidence("hlsHDRNoSubtitles")
        for row in frames:
            row["testPattern"] = False
        self.assertIn("expectedPictureNotObserved",
                      capture.assess_samples(samples, frames, control, "hlsHDRNoSubtitles")["gaps"])
        samples, frames, control = self.evidence("hlsHDRNoSubtitles")
        control["results"][0]["route"] = "hls"
        with self.assertRaisesRegex(capture.CaptureError, "wrongControlCase"):
            capture.assess_samples(samples, frames, control, "hlsHDRNoSubtitles")
        samples, frames, control = self.evidence("hlsHDRNoSubtitles")
        for row in frames:
            row["anyCue"] = True
        self.assertIn("unexpectedSubtitles",
                      capture.assess_samples(samples, frames, control, "hlsHDRNoSubtitles")["gaps"])

    def test_transport_override_validation_and_preparation(self):
        fixtures = {}
        for case, ext in zip(capture.CONTROL_CASES, ("m2ts", "ts", "MTS", "m2ts")):
            path = self.root / f"{case}.{ext}"
            path.write_bytes(b"fixture")
            fixtures[case] = str(path)
        config = dict(self.config, cases=list(capture.CONTROL_CASES), fixtureOverrides=fixtures)
        del config["hdrFixture"]
        self.assertEqual(capture.validate_config(config), list(capture.CONTROL_CASES))
        with mock.patch.object(capture, "probe_fixture", return_value={"checked": True}) as probe:
            prepared = capture.prepare_fixtures(config, config["cases"], self.root, self.root)
            self.assertEqual(set(prepared), set(capture.CONTROL_CASES))
            self.assertEqual(probe.call_count, 4)
            self.assertEqual(prepared["hlsNoSubtitles"][0], Path(fixtures["hlsNoSubtitles"]).resolve())
        for overrides in ({"camera": self.fixture}, {"directHDR": "relative.ts"},
                          {"directHDR": "https://example.invalid/live.ts"}, [], {"directHDR": str(self.root)}):
            with self.subTest(overrides=overrides), self.assertRaises(capture.CaptureError):
                capture.validate_config(dict(config, fixtureOverrides=overrides))

    def test_probe_rejects_multiple_programs_before_audio_checks(self):
        def probe_output(command):
            self.assertEqual(command[0], "ffprobe")
            self.assertIn("program=program_id", command)
            return json.dumps({"format": {"format_name": "mpegts", "duration": "60"},
                               "programs": [{"program_id": 1}, {"program_id": 2}]}).encode()

        with mock.patch.object(capture, "bounded_command", side_effect=probe_output) as command:
            with self.assertRaisesRegex(capture.CaptureError, "unsupportedFixturePrograms"):
                capture.probe_fixture(self.fixture, "ffmpeg", "ffprobe", hdr=False)
            self.assertEqual(command.call_count, 1)

    def test_probe_accepts_flac_and_still_requires_audible_intervals(self):
        import array
        probe = {"format": {"format_name": "matroska", "duration": "60"}, "streams": [
            {"codec_type": "video", "codec_name": "h264"},
            {"codec_type": "audio", "codec_name": "flac", "channels": 6, "index": 1}]}
        signal = array.array("f", [0.1] * 100).tobytes()
        with mock.patch.object(capture, "bounded_command", side_effect=[json.dumps(probe).encode(), signal, signal]):
            self.assertEqual(capture.probe_fixture(self.fixture, "ffmpeg", "ffprobe", hdr=False)["audioCodec"], "flac")
        with mock.patch.object(capture, "bounded_command", side_effect=[json.dumps(probe).encode(), bytes(400)]):
            with self.assertRaisesRegex(capture.CaptureError, "fixtureHasSilentTestInterval"):
                capture.probe_fixture(self.fixture, "ffmpeg", "ffprobe", hdr=False)

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
        subtitles = case not in {"hlsNoSubtitles", "hlsHDRNoSubtitles"}
        for index in range(18):
            uptime = 102 + index * .5
            name = f"frame-{index + 1:03d}.png"
            rows.extend([{"kind": "video", "uptime": uptime, "frame": name},
                         {"kind": "audio", "uptime": uptime, "rmsDBFS": -25}])
            frames.append({"frame": name, "anyCue": subtitles, "expectedCue": subtitles,
                           "centralDifference": 5, "testPattern": True})
        samples = {"schemaVersion": 1, "sourceVerified": True, "complete": True, "rows": rows}
        control = {"outcome": capture.CONTROL_PASS, "results": [{"cleanupConfirmed": True,
            "route": capture.CASE_INFO[case][1], "subtitlesRequested": subtitles,
            "startedAtUptime": 100, "elapsedSeconds": 11, "events": [{"kind": "playing", "origin": "receiver", "seconds": 1}]}]}
        return samples, frames, control

    def test_evidence_for_each_case(self):
        for case in capture.CONTROL_CASES:
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

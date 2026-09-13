"""Offline timing evidence tests; no application, receiver or input is opened."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Scripts"))
from playback_capture import CaptureError, CONTROL_PASS
from playback_startup import assess_startup


class StartupTimingTests(unittest.TestCase):
    token = "123456"

    def evidence(self, baseline=False):
        video, audio, analysis = [], [], []
        for n in range(35):
            when = 99 + n * .5
            positive = when >= 102
            frame = f"frame-{n + 1:03d}.png"
            video.append(dict(kind="video", uptime=when, frame=frame))
            analysis.append(dict(frame=frame, anyCue=positive, expectedCue=positive,
                                 testPattern=positive, centralDifference=5 if positive else 0,
                                 cueTokens=[self.token] if positive else []))
        for n in range(86):
            when = 99 + n * .2
            positive = when >= 101.4
            audio.append(dict(kind="audio", uptime=when, rmsDBFS=-20 if positive else -160,
                              testToneHz=880 if positive else 0))
        result = dict(profile="controls", route="hls", subtitlesRequested=True,
                      cleanupConfirmed=True, unverifiedChecks=[], startedAtUptime=99.5, elapsedSeconds=17,
                      events=[dict(kind="playing", origin="receiver", seconds=3.5),
                              dict(kind="paused", origin="receiver", seconds=10)])
        if baseline:
            result["playRequestedAtUptime"] = 100
        else:
            result["startups"] = [dict(label="initial", requestedAtUptime=100)]
        return (dict(schemaVersion=1, complete=True, sourceVerified=True,
                     rows=sorted(video + audio, key=lambda row: row["uptime"])),
                analysis, dict(outcome=CONTROL_PASS, results=[result]))

    def test_baseline_and_candidate_use_play_not_analysis_or_receiver(self):
        for baseline in (False, True):
            observed = assess_startup(*self.evidence(baseline), self.token)
            self.assertEqual(observed["outcome"], "sampled_startup_observed")
            self.assertAlmostEqual(observed["picture"]["firstPositiveSeconds"], 2)
            self.assertAlmostEqual(observed["picture"]["confirmedBySeconds"], 2.5)
            self.assertAlmostEqual(observed["audio"]["firstPositiveSeconds"], 1.4)
            self.assertTrue(observed["limits"])

    def test_missing_or_ambiguous_anchor_never_uses_started_at(self):
        for change in [lambda r: r.pop("startups"),
                       lambda r: r.update(playRequestedAtUptime=100),
                       lambda r: r["startups"][0].update(requestedAtUptime=99),
                       lambda r: r["startups"][0].update(requestedAtUptime=104),
                       lambda r: r["startups"][0].update(requestedAtUptime=float("nan")),
                       lambda r: r["startups"][0].update(label="warmReplay"),
                       lambda r: r.update(profile="hlsCacheReuse")]:
            evidence = self.evidence()
            change(evidence[2]["results"][0])
            with self.assertRaises(CaptureError): assess_startup(*evidence, self.token)

    def test_absent_prior_audio_is_unknown_not_silence(self):
        samples, frames, control = self.evidence()
        samples["rows"] = [r for r in samples["rows"] if r["kind"] != "audio" or r["uptime"] >= 100]
        result = assess_startup(samples, frames, control, self.token)
        self.assertIn("missingSilentAudioPreroll", result["gaps"])
        self.assertIsNone(result["picture"])
        self.assertIsNone(result["audio"])

    def test_previous_cue_picture_or_sound_cannot_be_reused(self):
        for kind in ("cue", "oldCue", "picture", "audio"):
            samples, frames, control = self.evidence()
            if kind == "cue":
                frames[0].update(expectedCue=True, anyCue=True, cueTokens=[self.token])
            elif kind == "oldCue":
                frames[0]["anyCue"] = True
            elif kind == "picture":
                frames[0]["testPattern"] = True
            else:
                samples["rows"][0 if samples["rows"][0]["kind"] == "audio" else 1]["rmsDBFS"] = -20
            observed = assess_startup(samples, frames, control, self.token)
            self.assertEqual(observed["outcome"], "inconclusive")
            self.assertIsNone(observed["picture"])
            self.assertIsNone(observed["audio"])

    def test_late_picture_after_pause_does_not_count_as_startup(self):
        samples, frames, control = self.evidence()
        control["results"][0]["events"].insert(0, dict(kind="seeked", origin="command", seconds=1.5))
        observed = assess_startup(samples, frames, control, self.token)
        self.assertIn("freshMovingFixtureNotObservedBeforeControls", observed["gaps"])

    def test_wrong_or_transient_tone_cannot_establish_sound(self):
        samples, frames, control = self.evidence()
        for row in samples["rows"]:
            if row["kind"] == "audio" and row["rmsDBFS"] > -60:
                row["testToneHz"] = 440
        observed = assess_startup(samples, frames, control, self.token)
        self.assertIn("fixtureAudioNotObservedBeforeControls", observed["gaps"])
        for row in samples["rows"]:
            if row["kind"] == "audio" and abs(row["uptime"] - 101.4) < .01:
                row["testToneHz"] = 880
        self.assertEqual(assess_startup(samples, frames, control, self.token)["outcome"], "inconclusive")

    def test_sampling_gap_and_invalid_early_values_do_not_pass(self):
        samples, frames, control = self.evidence()
        samples["rows"] = [r for r in samples["rows"] if r["kind"] != "audio" or not 100 <= r["uptime"] < 101.4]
        self.assertIn("audioSamplingGapAtStartup", assess_startup(samples, frames, control, self.token)["gaps"])
        samples, frames, control = self.evidence()
        frames[0]["expectedCue"] = "false"
        with self.assertRaises(CaptureError): assess_startup(samples, frames, control, self.token)
        samples, frames, control = self.evidence()
        frames[0]["cueTokens"] = ["654321"]
        with self.assertRaises(CaptureError): assess_startup(samples, frames, control, self.token)

    def test_offline_cli_preserves_inputs_and_existing_output(self):
        with tempfile.TemporaryDirectory(prefix="airciller-startup-evidence-") as temporary:
            directory = Path(temporary)
            (directory / "capture").mkdir()
            samples, frames, control = self.evidence(baseline=True)
            inputs = {directory / "capture/samples.json": samples,
                      directory / "frame-analysis.json": frames, directory / "controls.json": control}
            for path, value in inputs.items(): path.write_text(json.dumps(value))
            original = {path: path.read_bytes() for path in inputs}
            output = directory / "timing.json"
            command = [sys.executable, str(Path(__file__).resolve().parents[1] / "Scripts/playback_startup.py"),
                       str(directory), "--cue-token", self.token, "--output", str(output)]
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            observed = json.loads(output.read_text())
            self.assertEqual(set(observed["inputSHA256"]), {"samples", "analysis", "control"})
            self.assertEqual(set(observed["evaluatorDependenciesSHA256"]), {"playback_capture.py"})
            saved = output.read_bytes()
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 2)
            self.assertEqual(output.read_bytes(), saved)
            self.assertEqual({path: path.read_bytes() for path in inputs}, original)
            (directory / "controls.json").write_bytes(b"x" * 2_000_001)
            self.assertEqual(subprocess.run(command[:-1] + [str(directory / "invalid.json")],
                                            capture_output=True).returncode, 2)
            self.assertFalse((directory / "invalid.json").exists())


if __name__ == "__main__":
    unittest.main()

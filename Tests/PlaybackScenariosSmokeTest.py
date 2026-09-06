"""Evidence and fixture-plan tests only. No receiver or capture input is opened."""
import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Scripts"))
import playback_capture as capture
import playback_scenarios as scenarios


class ScenarioTests(unittest.TestCase):
    tokens = ["123456", "654321"]

    def evidence(self, name="hlsTrackChanges"):
        windows, rows, frames, events = [], [], [], []
        for n, (label, route, token, tone) in enumerate(scenarios.expected_windows(name, self.tokens)):
            start = 102 + n * 10
            windows.append(dict(label=label, startedAtUptime=start, endedAtUptime=start + 5))
            events.append(dict(kind="playing", origin="receiver", seconds=start - 100, position=0))
            for i in range(11):
                frame = f"frame-{len(frames) + 1:03d}.png"
                rows.extend([dict(kind="video", uptime=start + i * .5, frame=frame),
                             dict(kind="audio", uptime=start + i * .5, rmsDBFS=-20, testToneHz=tone or 440)])
                frames.append(dict(frame=frame, anyCue=token is not None, expectedCue=token is not None,
                                   cueTokens=[token] if token else [], centralDifference=5, testPattern=route == "hls"))
        if name == "playlistTransition": events.insert(1, dict(kind="ended", origin="receiver", seconds=9))
        samples = dict(schemaVersion=1, complete=True, sourceVerified=True, rows=rows)
        result = dict(profile=capture.CASE_INFO[name][0], route=capture.CASE_INFO[name][1], subtitlesRequested=True,
                      cleanupConfirmed=True, unverifiedChecks=[], startedAtUptime=100, elapsedSeconds=40,
                      outputWindows=windows, events=events,
                      loadSequence=[1, 2] if name == "playlistTransition" else [1],
                      completedSteps=["exactly_one_playlist_transition"] if name == "playlistTransition" else [])
        return samples, frames, dict(outcome=capture.CONTROL_PASS, results=[result])

    def test_phase_outputs(self):
        for name in ("hlsTrackChanges", "directTrackChanges", "playlistTransition"):
            with self.subTest(name=name):
                observed = scenarios.assess_scenario(*self.evidence(name), name, self.tokens)
                self.assertEqual(observed["outcome"], capture.OUTPUT_PASS)

    def test_missing_wrong_or_reordered_windows(self):
        for change in [lambda r: r["outputWindows"].pop(),
                       lambda r: r["outputWindows"].reverse(),
                       lambda r: r["outputWindows"][1].update(startedAtUptime=103),
                       lambda r: r["outputWindows"][1].update(endedAtUptime=float("nan")),
                       lambda r: r.update(loadSequence=[1, 1]),
                       lambda r: r.update(events=[]),
                       lambda r: r.update(events=[dict(e, origin="command") for e in r["events"]]),
                       lambda r: r.update(cleanupConfirmed=False)]:
            evidence = self.evidence()
            change(evidence[2]["results"][0])
            with self.assertRaises(capture.CaptureError):
                scenarios.assess_scenario(*evidence, "hlsTrackChanges", self.tokens)

    def test_old_cue_cannot_pass_subtitle_change(self):
        samples, frames, control = self.evidence()
        for row in frames:
            if row["cueTokens"] == [self.tokens[1]]: row["cueTokens"] = [self.tokens[0]]
        result = scenarios.assess_scenario(samples, frames, control, "hlsTrackChanges", self.tokens)
        self.assertIn("expectedSubtitleCueNotObserved", result["gaps"])

    def test_audio_must_change_and_be_measured(self):
        for value in (880, None, float("nan")):
            samples, frames, control = self.evidence()
            for row in samples["rows"]:
                if row["kind"] == "audio": row["testToneHz"] = value
            result = scenarios.assess_scenario(samples, frames, control, "hlsTrackChanges", self.tokens)
            self.assertIn("expectedAudioTrackNotObserved", result["gaps"])

    def test_playlist_requires_one_real_end_and_one_load(self):
        for change in [lambda r: r.update(loadSequence=[1, 2, 2]),
                       lambda r: r.update(completedSteps=[]),
                       lambda r: r.update(events=[e for e in r["events"] if e["kind"] != "ended"]),
                       lambda r: r["events"].append(dict(kind="ended", origin="receiver", seconds=29))]:
            evidence = self.evidence("playlistTransition")
            change(evidence[2]["results"][0])
            with self.assertRaises(capture.CaptureError):
                scenarios.assess_scenario(*evidence, "playlistTransition", self.tokens)

    def test_fixture_requirements_and_default_cases(self):
        self.assertEqual(capture.BASIC_CASES, ("directHDR", "hlsSubtitles", "hlsNoSubtitles"))
        self.assertTrue(capture.needs_hdr(["directTrackChanges"]))
        self.assertFalse(capture.needs_hls(["directTrackChanges"]))
        self.assertTrue(capture.needs_hls(["playlistTransition"]))
        self.assertTrue(capture.needs_hdr(["playlistTransition"]))
        self.assertFalse(capture.needs_hdr(["cancelPreparation"]))

    def test_long_pause_needs_duration_same_position_and_receiver_evidence(self):
        for name in ("directLongPause", "hlsLongPause"):
            samples, frames, control = self.evidence(name)
            result = control["results"][0]
            result.update(elapsedSeconds=380,
                          pauseWindow=dict(label="paused", startedAtUptime=108, endedAtUptime=468),
                          completedSteps=["paused_seek_acknowledged", "six_minute_pause_same_session", "resume_same_position_without_reload", "stop_and_cleanup"])
            result["outputWindows"][1].update(startedAtUptime=469, endedAtUptime=474)
            result["events"] = [dict(kind="playing", origin="receiver", seconds=2, position=0),
                                dict(kind="paused", origin="receiver", seconds=7.5),
                                dict(kind="seeked", origin="command", seconds=7.8, position=15, requestID="known-seek"),
                                dict(kind="resumed", origin="receiver", seconds=369, position=15)]
            for row in samples["rows"]:
                if row["uptime"] >= 112: row["uptime"] += 357
            self.assertEqual(scenarios.assess_scenario(samples, frames, control, name, self.tokens)["outcome"], capture.OUTPUT_PASS)
            # A short loading transition between Resume and confirmed output is normal;
            # loading during the six-minute hold or a sampled playback window is not.
            resumed_loading = copy.deepcopy(control)
            resumed_loading["results"][0]["events"].insert(-1, dict(kind="waiting", origin="helper", seconds=368.5))
            self.assertEqual(scenarios.assess_scenario(samples, frames, resumed_loading, name, self.tokens)["outcome"], capture.OUTPUT_PASS)
            for change in [lambda r: r["pauseWindow"].update(endedAtUptime=467),
                           lambda r: r["events"].pop(1),
                           lambda r: r["events"].pop(2),
                           lambda r: r["events"][2].update(position=25),
                           lambda r: r["events"][-1].update(position=0),
                           lambda r: r["events"][-1].update(origin="command"),
                           lambda r: r.update(loadSequence=[1, 1]),
                           lambda r: r["events"].append(dict(kind="stopped", origin="helper", seconds=100)),
                           lambda r: r["events"].append(dict(kind="waiting", origin="helper", seconds=100)),
                           lambda r: r["events"].append(dict(kind="waiting", origin="helper", seconds=371)),
                           lambda r: r["events"].append(dict(kind="status", origin="receiver", seconds=100, playing=True))]:
                modified = copy.deepcopy(control)
                change(modified["results"][0])
                with self.assertRaises(capture.CaptureError):
                    scenarios.assess_scenario(samples, frames, modified, name, self.tokens)

    def test_cancellation_requires_actual_work_and_no_playback(self):
        result = dict(profile="cancelPreparation", cleanupConfirmed=True, unverifiedChecks=[],
                      outputWindows=[], loadSequence=[1], events=[], completedSteps=[
                          "running_preparation_observed", "preparation_cancelled",
                          "no_delayed_playback_after_stop", "stop_and_cleanup"])
        control = dict(outcome=capture.CONTROL_PASS, results=[result])
        self.assertEqual(scenarios.assess_cancellation(control)["outcome"], capture.CANCELLATION_PASS)
        for change in [lambda r: r["completedSteps"].pop(0),
                       lambda r: r["events"].append(dict(kind="playing", origin="receiver")),
                       lambda r: r.update(cleanupConfirmed=False),
                       lambda r: r.update(loadSequence=[1, 2])]:
            modified = copy.deepcopy(control)
            change(modified["results"][0])
            with self.assertRaises(capture.CaptureError): scenarios.assess_cancellation(modified)


if __name__ == "__main__":
    unittest.main()

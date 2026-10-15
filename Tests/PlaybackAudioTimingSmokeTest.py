"""Deterministic timing-evaluator cases; no receiver or capture input."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Scripts"))
from playback_audio_timing import assess_audio_timing, expected_tone
from playback_capture import CONTROL_PASS, OUTPUT_PASS, CaptureError, assess_samples


def fixture(delay=5):
    name = "hlsAudioDelayTail" if delay > 0 else "hlsAudioAdvanceTail"
    beginning = 100.0
    timing = {"requestedDelay": delay, "sourceDuration": 60, "presentationDuration": 65,
              "videoContentOffset": 0 if delay > 0 else 5, "playRequestedAtUptime": beginning,
              "resumePosition": 56, "resumeEventSeconds": 40, "endEventSeconds": 49}
    result = {"profile": name, "route": "hls", "cleanupConfirmed": True,
              "unverifiedChecks": [], "loadSequence": [1], "startedAtUptime": beginning, "elapsedSeconds": 50,
              "completedSteps": ["audio_timing_pause_same_session", "audio_timing_seek_resume_same_session",
                                 "audio_timing_complete_tail", "stop_and_cleanup"],
              "audioTiming": timing, "outputWindows": [
                  {"label": "initial", "startedAtUptime": 100, "endedAtUptime": 112},
                  {"label": "afterPause", "startedAtUptime": 125, "endedAtUptime": 130}]}
    rows, analysis = [], []
    for index in range(48):
        presentation = index / 4
        clock = max(0, presentation - (5 if delay < 0 else 0))
        frame = f"frame-{index:03d}.png"
        rows.append({"kind": "video", "uptime": beginning + presentation, "frame": frame})
        analysis.append({"frame": frame, "fixtureTimeSeconds": clock, "cueTokens": ["123456"],
                         "fixtureCueIndex": 1 if clock < 10 else 2})
        audio_time = presentation - (5 if delay > 0 else 0)
        rows.append({"kind": "audio", "uptime": beginning + presentation,
                     "rmsDBFS": -100 if audio_time < 0 else -20,
                     "testToneHz": None if audio_time < 0 else expected_tone(audio_time)})
    for time in [146, 146.5, 147, 147.5, 148]:
        rows.append({"kind": "audio", "uptime": time, "rmsDBFS": -20, "testToneHz": 440})
    if delay < 0:
        # The controls and captured source clock describe three independent
        # preparations, including a changed presentation offset in the middle.
        rows = [row for row in rows if row["uptime"] < 140]
        result.update(elapsedSeconds=75, events=[])
        result["outputWindows"][1]["endedAtUptime"] = 132
        timing.update(resumeEventSeconds=65, endEventSeconds=74, transitions=[])
        result["completedSteps"].append("audio_timing_source_history_saved")
        for index, (label, phase_delay) in enumerate([
                ("timingReplay", -5), ("timingDelayChanged", 5), ("timingAdvanceRestored", -5)]):
            start, source = 135 + index * 10, 20 + index * 5
            offset = max(0, -phase_delay)
            phase = {"label": label, "requestedDelay": phase_delay, "expectedMoviePosition": source,
                     "expectedReceiverPosition": source + offset, "receiverPosition": source + offset,
                     "receiverEventSeconds": start - beginning, "videoContentOffset": offset}
            if index == 0:
                phase.update(savedMoviePosition=source, savedMovieDuration=60)
            timing["transitions"].append(phase)
            result["events"].append({"kind": "playing", "origin": "receiver", "seconds": start - beginning,
                                     "position": source + offset})
            result["completedSteps"].append(label)
            result["outputWindows"].append({"label": label, "startedAtUptime": start, "endedAtUptime": start + 7})
            for frame_index in range(28):
                clock = source + frame_index / 4
                uptime = start + frame_index / 4
                frame = f"transition-{index}-{frame_index}.png"
                rows.append({"kind": "video", "uptime": uptime, "frame": frame})
                rows.append({"kind": "audio", "uptime": uptime, "rmsDBFS": -20,
                             "testToneHz": expected_tone(clock - phase_delay)})
                analysis.append({"frame": frame, "fixtureTimeSeconds": clock, "cueTokens": ["123456"],
                                 "fixtureCueIndex": 3 if clock < 30 else 4})
    return {"rows": rows}, analysis, {"outcome": CONTROL_PASS, "results": [result]}, name


def moderate_cadence_fixture(delay=5):
    samples, analysis, control, name = fixture(delay)
    samples.update(schemaVersion=1, sourceVerified=True, complete=True)
    control["results"][0]["subtitlesRequested"] = True
    # Independent picture capture can arrive at a lower cadence than the audio.
    # Keep the actual seven-second observation, without inventing extra frames.
    samples["rows"] = [row for row in samples["rows"]
                       if row["kind"] != "video" or not row["frame"].startswith("frame-")]
    analysis[:] = [row for row in analysis if not row["frame"].startswith("frame-")]
    for index in range(15):
        presentation = .1 + index * .8
        clock = max(0, presentation - max(0, -delay))
        frame = f"moderate-{index}.png"
        samples["rows"].append({"kind": "video", "uptime": 100 + presentation, "frame": frame})
        analysis.append({"frame": frame, "fixtureTimeSeconds": clock, "cueTokens": ["123456"],
                         "fixtureCueIndex": 1 if clock < 10 else 2})
    for index in range(28 if delay < 0 else 20):
        progress = index / 4
        clock = 20 + progress
        frame = f"after-pause-{index}.png"
        samples["rows"].extend([
            {"kind": "video", "uptime": 125 + progress, "frame": frame},
            {"kind": "audio", "uptime": 125 + progress, "rmsDBFS": -20,
             "testToneHz": expected_tone(clock - delay)},
        ])
        analysis.append({"frame": frame, "fixtureTimeSeconds": clock, "cueTokens": ["123456"],
                         "fixtureCueIndex": 3})
    if delay < 0:
        # The last transition is the phase where a real five-second capture
        # lacked its sixth usable frame. Exercise its slower cadence too.
        samples["rows"] = [row for row in samples["rows"]
                           if row["kind"] != "video" or not row["frame"].startswith("transition-2-")]
        analysis[:] = [row for row in analysis if not row["frame"].startswith("transition-2-")]
        for index in range(9):
            progress = .1 + index * .8
            frame = f"moderate-final-{index}.png"
            samples["rows"].append({"kind": "video", "uptime": 155 + progress, "frame": frame})
            analysis.append({"frame": frame, "fixtureTimeSeconds": 30 + progress, "cueTokens": ["123456"],
                             "fixtureCueIndex": 4})
    for frame in analysis:
        frame.update(anyCue=True, expectedCue=True, testPattern=True, centralDifference=3)
    samples["rows"].sort(key=lambda row: row["uptime"])
    return samples, analysis, control, name


class TimingTests(unittest.TestCase):
    def evaluate(self, inputs):
        # The existing shared audiovisual evaluator has its own strict suite.
        # Isolate the additional clock/tone/tail assertions in these tests.
        with patch("playback_audio_timing.assess_samples", return_value={"outcome": OUTPUT_PASS, "gaps": []}):
            return assess_audio_timing(*inputs, ["123456", "654321"])

    def test_both_directions(self):
        for delay in (5, -5):
            self.assertEqual(self.evaluate(fixture(delay))["outcome"], OUTPUT_PASS)

    def test_moderate_cadence_observes_seven_seconds_after_opening_hold(self):
        for delay in (5, -5):
            with self.subTest(delay=delay):
                inputs = moderate_cadence_fixture(delay)
                original = copy.deepcopy(inputs)
                short_window = copy.deepcopy(inputs[2])
                short_window["results"][0].update(startedAtUptime=107, elapsedSeconds=5,
                                                 events=[{"kind": "playing", "origin": "receiver", "seconds": 0}])
                with self.assertRaisesRegex(CaptureError, "insufficientCapturedFrames"):
                    assess_samples(inputs[0], inputs[1], short_window, "hlsSubtitles")
                result = assess_audio_timing(*inputs, ["123456", "654321"])
                self.assertEqual(result["outcome"], OUTPUT_PASS)
                self.assertEqual(result["windows"][0]["frames"], 8)
                if delay < 0:
                    self.assertEqual(result["windows"][-1]["frames"], 8)
                    self.assertGreaterEqual(result["transitions"][-1]["matchingClockFrames"], 6)
                self.assertEqual(inputs, original)

    def test_negative_phases_require_seven_seconds_of_actual_observation(self):
        for label in ("afterPause", "timingReplay", "timingDelayChanged", "timingAdvanceRestored"):
            with self.subTest(window=label):
                inputs = moderate_cadence_fixture(-5)
                window = next(row for row in inputs[2]["results"][0]["outputWindows"] if row["label"] == label)
                window["endedAtUptime"] = window["startedAtUptime"] + 6.9
                with self.assertRaisesRegex(CaptureError, "shortAudioTimingResume"):
                    assess_audio_timing(*inputs, ["123456", "654321"])

    def test_negative_phases_keep_two_second_scheduling_allowance(self):
        inputs = moderate_cadence_fixture(-5)
        window = inputs[2]["results"][0]["outputWindows"][-1]
        window["endedAtUptime"] = window["startedAtUptime"] + 7.1
        self.assertEqual(assess_audio_timing(*inputs, ["123456", "654321"])["outcome"], OUTPUT_PASS)
        window["endedAtUptime"] = window["startedAtUptime"] + 9.01
        with self.assertRaisesRegex(CaptureError, "shortAudioTimingResume"):
            assess_audio_timing(*inputs, ["123456", "654321"])

    def test_larger_opening_still_requires_six_distinct_frames(self):
        inputs = moderate_cadence_fixture()
        inputs[0]["rows"] = [row for row in inputs[0]["rows"]
                             if row["kind"] != "video" or not 105.5 <= row["uptime"] < 108]
        with self.assertRaisesRegex(CaptureError, "insufficientCapturedFrames"):
            assess_audio_timing(*inputs, ["123456", "654321"])

    def test_larger_opening_still_requires_start_coverage(self):
        inputs = moderate_cadence_fixture()
        inputs[0]["rows"] = [row for row in inputs[0]["rows"]
                             if row["kind"] != "video" or not 105.5 <= row["uptime"] <= 111.5]
        for index in range(6):
            frame = f"late-{index}.png"
            inputs[0]["rows"].append({"kind": "video", "uptime": 108 + index / 2, "frame": frame})
            inputs[1].append({"frame": frame, "fixtureTimeSeconds": 8 + index / 2, "cueTokens": ["123456"],
                              "fixtureCueIndex": 1, "anyCue": True, "testPattern": True, "centralDifference": 3})
        inputs[0]["rows"].sort(key=lambda row: row["uptime"])
        with self.assertRaisesRegex(CaptureError, "captureDoesNotCoverPlayback"):
            assess_audio_timing(*inputs, ["123456", "654321"])

    def test_unshifted_audio_rejected(self):
        inputs = fixture()
        for row in inputs[0]["rows"]:
            if row["kind"] == "audio" and row["uptime"] < 112:
                row.update(rmsDBFS=-20, testToneHz=expected_tone(row["uptime"] - 100))
        result = self.evaluate(inputs)
        self.assertIn("requestedInitialAudioDelayNotObserved", result["gaps"])
        self.assertIn("audioVideoOffsetNotObserved", result["gaps"])

    def test_missing_clock_is_not_pass(self):
        inputs = fixture()
        for row in inputs[1]:
            row.pop("fixtureTimeSeconds")
        self.assertEqual(self.evaluate(inputs)["outcome"], "inconclusive")

    def test_wrong_subtitle_interval_rejected(self):
        inputs = fixture()
        for frame in inputs[1]:
            frame["fixtureCueIndex"] = 5
        self.assertIn("subtitleClockNotObserved", self.evaluate(inputs)["gaps"])

    def test_truncated_audio_tail(self):
        inputs = fixture()
        inputs[0]["rows"] = [row for row in inputs[0]["rows"] if row["uptime"] < 140]
        self.assertIn("delayedAudioTailNotObserved", self.evaluate(inputs)["gaps"])

    def test_early_receiver_end(self):
        inputs = fixture()
        inputs[2]["results"][0]["audioTiming"]["endEventSeconds"] = 44
        self.assertIn("completeTailNotEstablished", self.evaluate(inputs)["gaps"])

    def test_final_held_picture_is_not_a_clock_for_tail_audio(self):
        inputs = fixture()
        inputs[1].append({"frame": "held-tail.png", "fixtureTimeSeconds": 59.8, "cueTokens": []})
        for index in range(8):
            time = 142 + index / 4
            inputs[0]["rows"].extend([
                {"kind": "video", "uptime": time, "frame": "held-tail.png"},
                {"kind": "audio", "uptime": time, "rmsDBFS": -20, "testToneHz": 880},
            ])
        self.assertEqual(self.evaluate(inputs)["outcome"], OUTPUT_PASS)

    def test_ack_or_timer_does_not_replace_receiver(self):
        inputs = fixture()
        inputs[2]["results"][0]["unverifiedChecks"] = ["receiver_position"]
        with self.assertRaises(CaptureError):
            self.evaluate(inputs)

    def test_shared_output_failure_is_retained(self):
        inputs = fixture()
        with patch("playback_audio_timing.assess_samples", return_value={"outcome": "inconclusive", "gaps": ["expectedSubtitleCueNotObserved"]}):
            result = assess_audio_timing(*inputs, ["123456", "654321"])
        self.assertEqual(result["outcome"], "inconclusive")

    def test_missing_transition_is_not_old_capture_acceptance(self):
        inputs = fixture(-5)
        inputs[2]["results"][0]["audioTiming"].pop("transitions")
        with self.assertRaises(CaptureError):
            self.evaluate(inputs)

    def test_presentation_time_saved_as_history_rejected(self):
        inputs = fixture(-5)
        inputs[2]["results"][0]["audioTiming"]["transitions"][0]["savedMoviePosition"] += 5
        with self.assertRaises(CaptureError):
            self.evaluate(inputs)

    def test_unchanged_receiver_target_after_delay_change_rejected(self):
        inputs = fixture(-5)
        inputs[2]["results"][0]["audioTiming"]["transitions"][1]["receiverPosition"] += 5
        with self.assertRaises(CaptureError):
            self.evaluate(inputs)

    def test_receiver_ack_is_not_transition_evidence(self):
        inputs = fixture(-5)
        inputs[2]["results"][0]["events"][1]["origin"] = "command"
        with self.assertRaises(CaptureError):
            self.evaluate(inputs)

    def test_wrong_movie_clock_despite_correct_receiver_rejected(self):
        inputs = fixture(-5)
        for frame in inputs[1]:
            if frame["frame"].startswith("transition-1-"):
                frame["fixtureTimeSeconds"] += 5
        self.assertIn("moviePositionNotRetained", self.evaluate(inputs)["gaps"])

    def test_missing_picture_from_one_transition_rejected(self):
        inputs = fixture(-5)
        for frame in inputs[1]:
            if frame["frame"].startswith("transition-0-"):
                frame.pop("fixtureTimeSeconds")
        result = self.evaluate(inputs)
        self.assertIn("moviePositionNotRetained", result["gaps"])
        self.assertIn("transitionAudioOffsetNotObserved", result["gaps"])

    def test_unchanged_audio_offset_in_changed_phase_rejected(self):
        inputs = fixture(-5)
        for row in inputs[0]["rows"]:
            if row["kind"] == "audio" and 145 <= row["uptime"] < 150:
                row["testToneHz"] = expected_tone(25 + row["uptime"] - 145 + 5)
        self.assertIn("transitionAudioOffsetNotObserved", self.evaluate(inputs)["gaps"])

    def test_missing_cue_clock_from_one_transition_rejected(self):
        inputs = fixture(-5)
        for frame in inputs[1]:
            if frame["frame"].startswith("transition-2-"):
                frame.pop("fixtureCueIndex")
        self.assertIn("transitionSubtitleClockNotObserved", self.evaluate(inputs)["gaps"])


if __name__ == "__main__":
    unittest.main()

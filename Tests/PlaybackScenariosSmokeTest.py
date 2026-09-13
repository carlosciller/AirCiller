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
        duration = 8 if name == "hlsCacheReuse" else 5
        for n, (label, route, token, tone) in enumerate(scenarios.expected_windows(name, self.tokens)):
            start = 102 + n * 10
            windows.append(dict(label=label, startedAtUptime=start, endedAtUptime=start + duration))
            events.append(dict(kind="playing", origin="receiver", seconds=start - 100, position=0))
            for i in range(duration * 2 + 1):
                frame = f"frame-{len(frames) + 1:03d}.png"
                rows.extend([dict(kind="video", uptime=start + i * .5, frame=frame),
                             dict(kind="audio", uptime=start + i * .5, rmsDBFS=-20, testToneHz=tone or 440)])
                frames.append(dict(frame=frame, anyCue=token is not None, expectedCue=token is not None,
                                   cueTokens=[token] if token else [], centralDifference=5, testPattern=route == "hls"))
        if name == "playlistTransition": events.insert(1, dict(kind="ended", origin="receiver", seconds=9))
        samples = dict(schemaVersion=1, complete=True, sourceVerified=True, rows=rows)
        result = dict(profile=capture.CASE_INFO[name][0], route=capture.CASE_INFO[name][1], subtitlesRequested=True,
                      cleanupConfirmed=True, unverifiedChecks=[], startedAtUptime=100,
                      elapsedSeconds=70 if name == "hlsCacheReuse" else 40,
                      outputWindows=windows, events=events,
                      loadSequence=[1, 2] if name == "playlistTransition" else [1],
                      completedSteps=["exactly_one_playlist_transition"] if name == "playlistTransition" else [])
        if name == "hlsCacheReuse":
            result["startups"] = []
            for n, (window, hit) in enumerate(zip(windows, [False, True, True, False, True, True, True])):
                requested = window["startedAtUptime"] - 2
                digest = ("b" if n in (3, 4) else "a") * 64
                names = ["audio-init.mp4", "audio-00000.m4s", "video-init.mp4", "video-00000.m4s"]
                stages = ["cacheLookup", "receiverRequest"] + ([] if hit else ["packaging"])
                result["startups"].append(dict(
                    label=window["label"], requestedAtUptime=requested,
                    receiverConfirmedAtUptime=requested + 1.5, cacheHit=hit, expectedCacheHit=hit,
                    snapshot=dict(startedAtUptimeSeconds=requested + .1, elapsedSeconds=1,
                                  outcome="receiverMediaRequest", spans=[dict(stage=s, state="completed",
                                  startSeconds=0, elapsedSeconds=.2) for s in stages]),
                    baseFingerprint=dict(files=[dict(name=name, bytes=100, sha256=digest) for name in names])))
        control = dict(outcome=capture.CONTROL_PASS, results=[result])
        if name == "hlsCacheReuse":
            control.update(hlsCacheMode="isolated", isolatedCacheCleanupConfirmed=True)
        return samples, frames, control

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

    def test_early_capture_gap_retains_later_windows_without_passing_batch(self):
        for name in ("hlsTrackChanges", "hlsCacheReuse"):
            samples, frames, control = self.evidence(name)
            first = control["results"][0]["outputWindows"][0]
            samples["rows"] = [row for row in samples["rows"] if not (
                row["kind"] == "video" and first["startedAtUptime"] <= row["uptime"] <= first["endedAtUptime"])]
            result = scenarios.assess_scenario(samples, frames, control, name, self.tokens)
            self.assertEqual(result["outcome"], "inconclusive")
            self.assertEqual(result["gaps"], ["insufficientCapturedFrames"])
            self.assertEqual(len(result["windows"]), len(control["results"][0]["outputWindows"]))
            self.assertEqual(result["windows"][0], dict(
                window=first["label"], outcome="inconclusive", gaps=["insufficientCapturedFrames"]))
            self.assertTrue(all(window["outcome"] == capture.OUTPUT_PASS for window in result["windows"][1:]))
            if name == "hlsCacheReuse":
                self.assertEqual(result["cacheReuse"]["outcome"], "cache_reuse_and_media_identity_observed")

    def test_multiple_capture_gaps_remain_independent_failures(self):
        samples, frames, control = self.evidence()
        windows = control["results"][0]["outputWindows"]
        samples["rows"] = [row for row in samples["rows"] if not (
            row["kind"] == "video" and any(
                window["startedAtUptime"] <= row["uptime"] <= window["endedAtUptime"]
                for window in (windows[0], windows[-1])))]
        result = scenarios.assess_scenario(samples, frames, control, "hlsTrackChanges", self.tokens)
        self.assertEqual(result["outcome"], "inconclusive")
        self.assertEqual([window["outcome"] for window in result["windows"]],
                         ["inconclusive", capture.OUTPUT_PASS, capture.OUTPUT_PASS, "inconclusive"])

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
        self.assertTrue(capture.needs_hls(["hlsCacheReuse"]))
        self.assertFalse(capture.needs_hdr(["hlsCacheReuse"]))

    def test_cache_reuse_requires_output_and_base_identity(self):
        self.assertEqual(scenarios.expected_windows("hlsCacheReuse", self.tokens), [
            ("cold", "hls", self.tokens[0], 880),
            ("warmReplay", "hls", self.tokens[0], 880),
            ("subtitleChanged", "hls", self.tokens[1], 880),
            ("audioChanged", "hls", self.tokens[1], 440),
            ("subtitleDelayChanged", "hls", self.tokens[1], 440),
            ("originalAudioRestored", "hls", self.tokens[1], 880),
            ("subtitlesOff", "hls", None, 880)])
        result = scenarios.assess_scenario(*self.evidence("hlsCacheReuse"), "hlsCacheReuse", self.tokens)
        self.assertEqual(result["outcome"], capture.OUTPUT_PASS)
        self.assertEqual(result["cacheReuse"]["outcome"], "cache_reuse_and_media_identity_observed")
        self.assertEqual(len(result["cacheReuse"]["starts"]), 7)
        self.assertEqual(result["cacheReuse"]["timingEndpoint"], "receiver_confirmation_not_first_visible_frame")
        for field, value in [("hlsCacheMode", "disabled"), ("isolatedCacheCleanupConfirmed", False)]:
            evidence = self.evidence("hlsCacheReuse")
            evidence[2][field] = value
            with self.assertRaises(capture.CaptureError):
                scenarios.assess_scenario(*evidence, "hlsCacheReuse", self.tokens)
        for change in [lambda r: r["startups"].pop(),
                       lambda r: r["startups"].reverse(),
                       lambda r: r["startups"][1].update(cacheHit=False),
                       lambda r: r["startups"][3].update(expectedCacheHit=True),
                       lambda r: r["startups"][1].update(baseFingerprint=r["startups"][4]["baseFingerprint"]),
                       lambda r: r["startups"][4].update(baseFingerprint=r["startups"][0]["baseFingerprint"]),
                       lambda r: r["startups"][5].update(baseFingerprint=r["startups"][3]["baseFingerprint"]),
                       lambda r: r["startups"][0].update(requestedAtUptime=float("nan")),
                       lambda r: r["startups"][1].update(requestedAtUptime=101),
                       lambda r: r["startups"][0].update(receiverConfirmedAtUptime=103),
                       lambda r: r["startups"][0]["snapshot"].update(spans=[]),
                       lambda r: r["startups"][1]["snapshot"]["spans"].append(
                           dict(stage="packaging", state="completed", startSeconds=0, elapsedSeconds=.2)),
                       lambda r: r["startups"][0]["snapshot"]["spans"][0].update(state="interrupted"),
                       lambda r: r["startups"][0]["baseFingerprint"]["files"][0].update(name="../source.mkv"),
                       lambda r: r["startups"][0]["baseFingerprint"]["files"][0].update(sha256="missing"),
                       lambda r: r["startups"][0]["baseFingerprint"]["files"][0].update(bytes=300 * 1024**2)]:
            evidence = self.evidence("hlsCacheReuse")
            change(evidence[2]["results"][0])
            with self.assertRaises(capture.CaptureError):
                scenarios.assess_scenario(*evidence, "hlsCacheReuse", self.tokens)

    def test_cache_hit_does_not_prove_audio_or_subtitles(self):
        samples, frames, control = self.evidence("hlsCacheReuse")
        for row in samples["rows"]:
            if row["kind"] == "audio": row["testToneHz"] = 880
        for frame in frames:
            if frame["cueTokens"] == [self.tokens[1]]: frame["cueTokens"] = [self.tokens[0]]
        result = scenarios.assess_scenario(samples, frames, control, "hlsCacheReuse", self.tokens)
        self.assertEqual(result["outcome"], "inconclusive")
        self.assertIn("expectedSubtitleCueNotObserved", result["gaps"])
        self.assertIn("expectedAudioTrackNotObserved", result["gaps"])

    def test_longer_cache_window_does_not_relax_required_frames(self):
        samples, frames, control = self.evidence("hlsCacheReuse")
        first = control["results"][0]["outputWindows"][0]
        self.assertEqual(first["endedAtUptime"] - first["startedAtUptime"], 8)
        retained = 0
        rows = []
        for row in samples["rows"]:
            if row["kind"] == "video" and first["startedAtUptime"] <= row["uptime"] <= first["endedAtUptime"]:
                retained += 1
                if retained > 5:
                    continue
            rows.append(row)
        samples["rows"] = rows
        result = scenarios.assess_scenario(samples, frames, control, "hlsCacheReuse", self.tokens)
        self.assertEqual(result["outcome"], "inconclusive")
        self.assertEqual(result["windows"][0]["gaps"], ["insufficientCapturedFrames"])
        self.assertTrue(all(window["outcome"] == capture.OUTPUT_PASS for window in result["windows"][1:]))

    def test_cache_all_phases_require_separate_audio_and_video(self):
        for index in range(7):
            samples, frames, control = self.evidence("hlsCacheReuse")
            start = control["results"][0]["startups"][index]
            start["baseFingerprint"]["files"] = [f for f in start["baseFingerprint"]["files"]
                                                  if not f["name"].startswith("audio-")]
            with self.assertRaises(capture.CaptureError):
                scenarios.assess_scenario(samples, frames, control, "hlsCacheReuse", self.tokens)

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

"""Assess fixed synthetic SDR +/-5 s timing cases from approved digital samples."""
import copy

from playback_capture import CONTROL_PASS, OUTPUT_PASS, CaptureError, assess_samples, finite


def expected_tone(source_time):
    return 880 if (int(source_time // 2) * 7 + 3) % 11 < 5 else 440


def assess_audio_timing(samples, analysis, control, name, tokens):
    try:
        delay = {"hlsAudioDelayTail": 5, "hlsAudioAdvanceTail": -5}[name]
        result = control["results"][0]
        timing = result["audioTiming"]
        required = {"audio_timing_pause_same_session", "audio_timing_seek_resume_same_session",
                    "audio_timing_complete_tail", "stop_and_cleanup"}
        if (control["outcome"] != CONTROL_PASS or len(control["results"]) != 1
                or result["profile"] != name or result["route"] != "hls"
                or result["cleanupConfirmed"] is not True or result["unverifiedChecks"]
                or result["loadSequence"] != [1] or not required.issubset(result["completedSteps"])
                or timing["requestedDelay"] != delay or not finite(timing["sourceDuration"])
                or abs(timing["sourceDuration"] - 60) > .2
                or not finite(timing["presentationDuration"]) or abs(timing["presentationDuration"] - 65) > .2
                or not finite(timing["videoContentOffset"])
                or abs(timing["videoContentOffset"] - (5 if delay < 0 else 0)) > .05):
            raise CaptureError("incompleteAudioTimingControls")
        began, elapsed = result["startedAtUptime"], result["elapsedSeconds"]
        requested = timing["playRequestedAtUptime"]
        if (not all(finite(v) for v in (began, elapsed, requested)) or not 0 < elapsed <= (165 if delay < 0 else 120)
                or not began <= requested < began + elapsed):
            raise CaptureError("invalidAudioTimingClock")
        windows = result["outputWindows"]
        transition_names = ["timingReplay", "timingDelayChanged", "timingAdvanceRestored"] if delay < 0 else []
        if [w["label"] for w in windows] != ["initial", "afterPause"] + transition_names:
            raise CaptureError("invalidAudioTimingWindows")
        transitions = timing.get("transitions", [])
        if [phase["label"] for phase in transitions] != transition_names:
            raise CaptureError("incompleteAudioTimingTransitions")
        if delay < 0 and not {"audio_timing_source_history_saved", *transition_names}.issubset(result["completedSteps"]):
            raise CaptureError("incompleteAudioTimingTransitions")
        phase_by_label = dict(zip(transition_names, transitions))
        previous_end = requested
        observed = []
        for window in windows:
            start, end = window["startedAtUptime"], window["endedAtUptime"]
            if not all(finite(v) for v in (start, end)) or not previous_end <= start < end <= began + elapsed:
                raise CaptureError("invalidAudioTimingWindows")
            if window["label"] in phase_by_label:
                phase = phase_by_label[window["label"]]
                expected_delay = 5 if window["label"] == "timingDelayChanged" else -5
                if (phase["requestedDelay"] != expected_delay
                        or not all(finite(phase[key]) for key in ("expectedMoviePosition", "expectedReceiverPosition",
                                                                  "receiverPosition", "receiverEventSeconds", "videoContentOffset"))
                        or not 5 < phase["expectedMoviePosition"] < 55
                        or abs(phase["videoContentOffset"] - max(0, -expected_delay)) > .05
                        or abs(phase["expectedReceiverPosition"] - phase["expectedMoviePosition"] - max(0, -expected_delay)) > .001
                        or abs(phase["receiverPosition"] - phase["expectedReceiverPosition"]) > 2
                        or not previous_end <= began + phase["receiverEventSeconds"] <= start + .1
                        or not any(event.get("origin") == "receiver" and event.get("kind") in ("playing", "resumed", "status")
                                   and (event.get("kind") in ("playing", "resumed") or event.get("playing") is True)
                                   and event.get("seconds") == phase["receiverEventSeconds"]
                                   and event.get("position") == phase["receiverPosition"] for event in result["events"])):
                    raise CaptureError("invalidAudioTimingTransition")
                if window["label"] == "timingReplay":
                    if (not finite(phase.get("savedMoviePosition")) or not finite(phase.get("savedMovieDuration"))
                            or abs(phase["savedMoviePosition"] - phase["expectedMoviePosition"]) > .002
                            or abs(phase["savedMovieDuration"] - timing["sourceDuration"]) > .002):
                        raise CaptureError("invalidAudioTimingHistory")
            previous_end = end
            if window["label"] == "initial":
                if not 12 <= end - start <= 14:
                    raise CaptureError("shortAudioTimingOpening")
                # Observe seven seconds after the deliberate five-second audio
                # delay/video hold. The shared evaluator still trims 0.5 s at
                # each end and requires six distinct frames and full coverage.
                start = end - 7
            else:
                minimum = 7 if delay < 0 else 5
                if not minimum <= end - start <= minimum + 2:
                    raise CaptureError("shortAudioTimingResume")
            proxy = copy.deepcopy(control)
            proxy["results"][0].update(startedAtUptime=start, elapsedSeconds=end - start,
                                      events=[{"kind": "playing", "origin": "receiver", "seconds": 0}])
            frames = [dict(row, expectedCue=tokens[0] in row.get("cueTokens", [])) for row in analysis]
            verdict = assess_samples(samples, frames, proxy, "hlsSubtitles")
            verdict["window"] = window["label"]
            observed.append(verdict)
        rows = samples["rows"]
        frame_map = {row["frame"]: row for row in analysis}
        clock_frames = [(row["uptime"], frame_map[row["frame"]]["fixtureTimeSeconds"])
                        for row in rows if row["kind"] == "video" and requested <= row["uptime"] <= began + elapsed
                        and finite(frame_map[row["frame"]].get("fixtureTimeSeconds"))]
        gaps = {gap for window in observed for gap in window["gaps"]}
        transition_checks = []
        for window in windows[2:]:
            phase = phase_by_label[window["label"]]
            # The visible source clock is independent of the receiver's claimed
            # position and of the coordinator's clock-conversion implementation.
            clocks = [(uptime, clock) for uptime, clock in clock_frames
                      if window["startedAtUptime"] + .5 <= uptime <= window["endedAtUptime"]]
            errors = [abs(clock - phase["expectedMoviePosition"] - (uptime - began - phase["receiverEventSeconds"]))
                      for uptime, clock in clocks]
            matched = sum(error <= 2 for error in errors)
            mismatched = sum(error > 2 for error in errors)
            if matched < 6 or mismatched:
                gaps.add("moviePositionNotRetained")
            transition_checks.append({"window": window["label"], "matchingClockFrames": matched,
                                      "mismatchingClockFrames": mismatched, "matchingTones": 0,
                                      "mismatchingTones": 0, "matchingCues": 0, "wrongCues": 0})
        check_by_label = {check["window"]: check for check in transition_checks}
        matching_cues = 0
        wrong_cues = 0
        boundaries = [0, 10, 20, 30, 45, 60]
        for row in rows:
            if row["kind"] != "video" or not any(
                    window["startedAtUptime"] <= row["uptime"] <= window["endedAtUptime"] for window in windows):
                continue
            frame = frame_map[row["frame"]]
            clock = frame.get("fixtureTimeSeconds")
            cue = frame.get("fixtureCueIndex")
            if not finite(clock) or type(cue) is not int or min(abs(clock - value) for value in boundaries) < .5:
                continue
            expected = next((index + 1 for index in range(5) if boundaries[index] <= clock < boundaries[index + 1]), None)
            if cue == expected:
                matching_cues += 1
            else:
                wrong_cues += 1
            window = next(w for w in windows if w["startedAtUptime"] <= row["uptime"] <= w["endedAtUptime"])
            if window["label"] in check_by_label:
                check_by_label[window["label"]]["matchingCues" if cue == expected else "wrongCues"] += 1
        if matching_cues < 6 or wrong_cues:
            gaps.add("subtitleClockNotObserved")
        opening = windows[0]
        initial_clocks = [clock for uptime, clock in clock_frames
                          if requested <= uptime <= opening["endedAtUptime"]]
        if not initial_clocks or min(initial_clocks) > 1:
            gaps.add("completeVideoOpeningNotObserved")
        matched = 0
        mismatched = 0
        silent = 0
        premature_audio = 0
        for row in rows:
            if row["kind"] != "audio" or not requested <= row["uptime"] <= began + elapsed:
                continue
            # Picture time is a usable clock only during the recorded stable
            # moving-video windows. A paused or final held image cannot date
            # later audio samples. Tail coverage has its own receiver/audio test.
            window = next((window for window in windows
                           if window["startedAtUptime"] <= row["uptime"] <= window["endedAtUptime"]), None)
            if window is None:
                continue
            nearest = min(clock_frames, key=lambda frame: abs(frame[0] - row["uptime"]), default=None)
            if nearest is None or abs(nearest[0] - row["uptime"]) > .35:
                continue
            clock = nearest[1]
            if delay > 0 and .5 <= clock <= 4:
                if row.get("rmsDBFS", -160) > -60:
                    premature_audio += 1
                elif finite(row.get("rmsDBFS")):
                    silent += 1
            window_delay = phase_by_label.get(window["label"], {}).get("requestedDelay", delay)
            audio_time = clock - window_delay
            # Exclude boundaries and the deliberately held opening image.
            if clock < .5 or not .5 <= audio_time <= 59.5 or not .45 < audio_time % 2 < 1.55:
                continue
            tone = row.get("testToneHz")
            if row.get("rmsDBFS", -160) <= -60 or not finite(tone):
                continue
            if abs(tone - expected_tone(audio_time)) < 35:
                matched += 1
                if window["label"] in check_by_label:
                    check_by_label[window["label"]]["matchingTones"] += 1
            else:
                mismatched += 1
                if window["label"] in check_by_label:
                    check_by_label[window["label"]]["mismatchingTones"] += 1
        if delay > 0 and (silent < 3 or premature_audio):
            gaps.add("requestedInitialAudioDelayNotObserved")
        if matched < 8 or mismatched > 1:
            gaps.add("audioVideoOffsetNotObserved")
        for check in transition_checks:
            if check["matchingTones"] < 3 or check["mismatchingTones"] > 1:
                gaps.add("transitionAudioOffsetNotObserved")
            if check["matchingCues"] < 3 or check["wrongCues"]:
                gaps.add("transitionSubtitleClockNotObserved")
        resumed = timing["resumeEventSeconds"]
        ended = timing["endEventSeconds"]
        position = timing["resumePosition"]
        if (not all(finite(v) for v in (resumed, ended, position)) or ended <= resumed
                or not timing["presentationDuration"] - position - 1 <= ended - resumed
                    <= timing["presentationDuration"] - position + 4):
            gaps.add("completeTailNotEstablished")
        if delay > 0:
            expected_end = began + resumed + timing["presentationDuration"] - position
            tail_audio = [row for row in rows if row["kind"] == "audio"
                          and expected_end - 3 <= row["uptime"] <= expected_end - .5
                          and row.get("rmsDBFS", -160) > -60 and finite(row.get("testToneHz"))]
            if len(tail_audio) < 3:
                gaps.add("delayedAudioTailNotObserved")
        return {"outcome": OUTPUT_PASS if not gaps else "inconclusive", "gaps": sorted(gaps),
                "controls": CONTROL_PASS, "windows": observed, "requestedDelaySeconds": delay,
                "clockFrames": len(clock_frames), "matchingToneMeasurements": matched,
                "mismatchingToneMeasurements": mismatched, "initialSilentMeasurements": silent,
                "prematureAudioMeasurements": premature_audio, "matchingCueMeasurements": matching_cues,
                "wrongCueMeasurements": wrong_cues, "transitions": transition_checks}
    except (KeyError, TypeError, ValueError, IndexError):
        raise CaptureError("invalidAudioTimingEvidence") from None

"""Additional opt-in checks. Basic three-case acceptance remains separate."""
import copy
import json
import secrets

from playback_checks import run_process
from playback_capture import (CASE_INFO, CONTROL_PASS, OUTPUT_PASS, CANCELLATION_PASS, CaptureError,
                              assess_samples, bounded_command, finite, fingerprint, read_json,
                              save_json, supervise_case, write_cues)


def expected_windows(name, tokens):
    route = CASE_INFO[name][1]
    initial = ("initial", route, tokens[0], 880 if route == "hls" else None)
    if CASE_INFO[name][0] == "longPause":
        return [initial, ("afterPause", route, tokens[0], 880 if route == "hls" else None)]
    if name == "playlistTransition":
        return [initial, ("nextItem", "hls", None, 880)]
    windows = [initial, ("subtitleChanged", route, tokens[1], 880 if route == "hls" else None)]
    if name == "hlsTrackChanges":
        windows.extend([("audioChanged", "hls", tokens[1], 440), ("subtitlesOff", "hls", None, 440)])
    return windows


def assess_cancellation(control):
    required = {"running_preparation_observed", "preparation_cancelled", "no_delayed_playback_after_stop", "stop_and_cleanup"}
    try:
        result = control["results"][0]
        if (control["outcome"] != CONTROL_PASS or len(control["results"]) != 1
                or result["profile"] != "cancelPreparation" or result["cleanupConfirmed"] is not True
                or result["unverifiedChecks"] or result["outputWindows"] or result["loadSequence"] != [1]
                or not required.issubset(result["completedSteps"])
                or any(e["kind"] == "playing" or (e["origin"] == "receiver" and e.get("playing") is True) for e in result["events"])):
            raise CaptureError("cancellationNotEstablished")
        return {"outcome": CANCELLATION_PASS, "gaps": [], "controls": CONTROL_PASS, "outputVerification": "not_started"}
    except (KeyError, TypeError, IndexError):
        raise CaptureError("invalidCancellationEvidence") from None


def assess_scenario(samples, analysis, control, name, tokens):
    try:
        expected = expected_windows(name, tokens)
        if not isinstance(control, dict) or not isinstance(analysis, list):
            raise CaptureError("invalidScenarioEvidence")
        result = control["results"][0]
        windows = result["outputWindows"]
        if (len(control["results"]) != 1 or control["outcome"] != CONTROL_PASS
                or result["profile"] != CASE_INFO[name][0] or result["cleanupConfirmed"] is not True
                or result["unverifiedChecks"] or len(windows) != len(expected)
                or result["route"] != CASE_INFO[name][1] or result["subtitlesRequested"] is not True
                or result["loadSequence"] != ([1, 2] if name == "playlistTransition" else [1])):
            raise CaptureError("incompleteScenarioControls")
        if name == "playlistTransition" and "exactly_one_playlist_transition" not in result["completedSteps"]:
            raise CaptureError("playlistTransitionNotEstablished")
        began, elapsed = result["startedAtUptime"], result["elapsedSeconds"]
        long_pause = CASE_INFO[name][0] == "longPause"
        if not finite(began) or not finite(elapsed) or began < 0 or not 0 < elapsed <= (480 if long_pause else 180):
            raise CaptureError("invalidScenarioTiming")
        previous_end = began
        events = result["events"]
        if not isinstance(events, list) or any(not isinstance(e, dict) for e in events):
            raise CaptureError("invalidScenarioEvents")
        if long_pause:
            assess_long_pause(result)
        if name == "playlistTransition" and sum(e.get("kind") == "ended" and e.get("origin") == "receiver" for e in events) != 1:
            raise CaptureError("playlistEndNotEstablished")
        output = []
        for window, (label, route, token, tone) in zip(windows, expected):
            start, end = window["startedAtUptime"], window["endedAtUptime"]
            if (window["label"] != label or not finite(start) or not finite(end) or not previous_end <= start < end <= began + elapsed
                    or not 4 <= end - start <= 10):
                raise CaptureError("invalidScenarioWindows")
            if not any(e.get("kind") in (("playing", "resumed") if long_pause else ("playing",)) and e.get("origin") == "receiver"
                       and finite(e.get("seconds")) and previous_end - began <= e["seconds"] <= start - began + .1
                       and finite(e.get("position")) for e in events):
                raise CaptureError("missingScenarioReceiverStart")
            previous_end = end
            proxy = copy.deepcopy(control)
            proxy["results"][0].update(route=route, subtitlesRequested=token is not None, startedAtUptime=start,
                elapsedSeconds=end - start, events=[{"kind": "playing", "origin": "receiver", "seconds": 0}])
            # Window boundaries are application observations. Passing receiver evidence
            # is required above; this proxy only selects the shared sampling interval.
            frames = []
            for row in analysis:
                if not isinstance(row, dict) or not isinstance(row.get("cueTokens"), list) or any(t not in tokens for t in row["cueTokens"]):
                    raise CaptureError("invalidScenarioCues")
                frames.append(dict(row, expectedCue=token is not None and token in row["cueTokens"]))
            base_case = "directHDR" if route == "directHDR" else ("hlsSubtitles" if token else "hlsNoSubtitles")
            observed = assess_samples(samples, frames, proxy, base_case)
            observed["window"] = label
            if tone is not None:
                audio = [r for r in samples["rows"] if r["kind"] == "audio" and start + .5 <= r["uptime"] <= end - .5
                         and r.get("rmsDBFS", -160) > -60]
                matched = sum(finite(r.get("testToneHz")) and abs(r["testToneHz"] - tone) < 35 for r in audio)
                observed.update(expectedToneHz=tone, matchingToneMeasurements=matched)
                if matched < 3:
                    observed["gaps"].append("expectedAudioTrackNotObserved")
                    observed["outcome"] = "inconclusive"
            output.append(observed)
        return {"outcome": OUTPUT_PASS if all(w["outcome"] == OUTPUT_PASS for w in output) else "inconclusive",
                "controls": CONTROL_PASS, "windows": output, "gaps": sorted({g for w in output for g in w["gaps"]})}
    except (KeyError, TypeError, IndexError, ValueError):
        raise CaptureError("invalidScenarioEvidence") from None


def assess_long_pause(result):
    pause = result["pauseWindow"]
    start, end = pause["startedAtUptime"], pause["endedAtUptime"]
    windows = result["outputWindows"]
    began = result["startedAtUptime"]
    required = {"paused_seek_acknowledged", "six_minute_pause_same_session", "resume_same_position_without_reload", "stop_and_cleanup"}
    if (pause["label"] != "paused" or not finite(start) or not finite(end) or not 360 <= end - start <= 365
            or not windows[0]["endedAtUptime"] <= start < end <= windows[1]["startedAtUptime"]
            or not required.issubset(result["completedSteps"])):
        raise CaptureError("longPauseNotEstablished")
    events = result["events"]
    paused = [e for e in events if e.get("origin") == "receiver" and e.get("kind") == "paused"
              and finite(e.get("seconds")) and windows[0]["endedAtUptime"] - began <= e["seconds"] <= start - began]
    seeks = [e for e in events if e.get("origin") == "command" and e.get("kind") == "seeked"
             and finite(e.get("seconds")) and windows[0]["endedAtUptime"] - began <= e["seconds"] <= start - began
             and finite(e.get("position")) and abs(e["position"] - 15) <= .1 and e.get("requestID")]
    resumed = [e for e in events if e.get("origin") == "receiver" and e.get("kind") == "resumed"
               and finite(e.get("seconds")) and end - began <= e["seconds"] <= windows[1]["startedAtUptime"] - began + .1
               and finite(e.get("position"))]
    if (not paused or len(seeks) != 1 or len(resumed) != 1 or paused[0]["seconds"] > seeks[0]["seconds"]
            or abs(resumed[0]["position"] - 15) > 2
            or sum(e.get("kind") == "playing" and e.get("origin") == "receiver" for e in events) != 1
            or any(e.get("kind") in ("error", "ended") or
                   (e.get("kind") == "waiting" and (
                       start - began <= e.get("seconds", -1) < end - began or
                       any(w["startedAtUptime"] - began <= e.get("seconds", -1) <= w["endedAtUptime"] - began for w in windows))) or
                   (e.get("kind") == "stopped" and e.get("seconds", 0) < windows[1]["endedAtUptime"] - began)
                   for e in events)
            or any(e.get("origin") == "receiver" and e.get("playing") is True
                   and start - began <= e.get("seconds", -1) < end - began for e in events)):
        raise CaptureError("longPauseReceiverMismatch")


def run_scenario(name, config, fixtures, project, directory, candidate_hash):
    directory.mkdir(mode=0o700)
    profile, route = CASE_INFO[name]
    fixture = fixtures[route]
    binary = project / ".build/AirCiller Playback Checks.app/Contents/MacOS/AirCiller"
    tools = project / ".build/playback-capture-tools"
    plan = {"version": 1, "deviceID": config["deviceID"], "profile": profile,
            "clips": [{"path": str(fixture[0]), "route": route}]}
    clip = plan["clips"][0]
    tokens = [f"{value:06d}" for value in secrets.SystemRandom().sample(range(1_000_000), 2)]
    if profile != "cancelPreparation":
        first = directory / "initial.eng.srt"
        write_cues(first, tokens[0])
        clip["externalSubtitle"] = str(first)
        if profile == "trackChanges":
            alternate = directory / "alternate.eng.srt"
            write_cues(alternate, tokens[1])
            clip["alternateSubtitle"] = str(alternate)
        elif profile == "playlistTransition":
            clip["nextClip"] = {"path": str(fixtures["hls"][0]), "route": "hls"}
        ready, stop = directory / "capture.ready", directory / "capture.stop"
        plan["captureReadyFile"] = str(ready)
        capture_dir = directory / "capture"
        capture_dir.mkdir(mode=0o700)
    plan_path, controls_path = directory / "plan.json", directory / "controls.json"
    save_json(plan_path, plan)
    result = {"case": name, "fixture": fixture[1], "outcome": "inconclusive"}
    if profile == "playlistTransition": result["nextFixture"] = fixtures["hls"][1]
    try:
        command = [str(binary), "--run", str(plan_path), "--report", str(controls_path), "--tv-is-idle"]
        if profile == "cancelPreparation":
            if run_process(command, timeout=90) is not None: raise CaptureError("cancellationRunFailed")
            result.update(assess_cancellation(read_json(controls_path)))
        else:
            source = config["captureSource"]
            supervise_case(command, [tools / "capture-samples", "--capture", source["uniqueID"], source["name"],
                                    capture_dir, ready, stop] + (["--long-pause"] if profile == "longPause" else []),
                           ready, stop, timeout=510 if profile == "longPause" else 180)
            controls = read_json(controls_path)
            samples = read_json(capture_dir / "samples.json")
            analysis = json.loads(bounded_command([tools / "analyze-frames", capture_dir, ",".join(tokens)], timeout=90))
            save_json(directory / "frame-analysis.json", analysis)
            result.update(assess_scenario(samples, analysis, controls, name, tokens))
            result["sampleManifestSHA256"] = fingerprint(capture_dir / "samples.json")
        if fingerprint(binary) != candidate_hash: raise CaptureError("candidateChangedDuringRun")
    except CaptureError as error:
        result.update(outcome="inconclusive", gaps=[str(error)])
    return result

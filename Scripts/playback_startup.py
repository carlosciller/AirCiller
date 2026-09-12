#!/usr/bin/env python3
"""Assess saved synthetic HLS startup samples. Never opens a media device."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat

from playback_capture import CaptureError, OUTPUT_PASS, assess_samples, finite, fingerprint, save_json


def read_evidence(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= 2_000_000:
            raise CaptureError("invalidTimingReport")
        data = source.read(2_000_001)
    if len(data) != info.st_size:
        raise CaptureError("timingReportChangedDuringRead")
    value = json.loads(data, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
    return value, hashlib.sha256(data).hexdigest()


def request_time(result):
    baseline = result.get("playRequestedAtUptime")
    starts = result.get("startups", [])
    if baseline is not None:
        if starts:
            raise CaptureError("ambiguousPlayTimestamp")
        requested = baseline
    else:
        if not isinstance(starts, list) or len(starts) != 1 or starts[0].get("label") != "initial":
            raise CaptureError("missingPlayTimestamp")
        requested = starts[0].get("requestedAtUptime")
    if (not finite(requested) or requested < result["startedAtUptime"]
            or requested >= result["startedAtUptime"] + result["elapsedSeconds"]):
        raise CaptureError("invalidPlayTimestamp")
    return requested


def onset(rows, matches, requested, deadline, count, maximum_gap):
    """First consecutive positive run; retain callback gaps, not a timing error bound."""
    selected = [row for row in rows if requested <= row["uptime"] < deadline]
    for index in range(len(selected) - count + 1):
        run = selected[index:index + count]
        if all(matches(row) for row in run) and all(
                0 < b["uptime"] - a["uptime"] <= maximum_gap for a, b in zip(run, run[1:])):
            prior = [row for row in rows if row["uptime"] < requested]
            observed = [prior[-1], *selected[:index + count]] if prior else selected[:index + count]
            gaps = [b["uptime"] - a["uptime"] for a, b in zip(observed, observed[1:])]
            return {"firstPositiveSeconds": run[0]["uptime"] - requested,
                    "confirmedBySeconds": run[-1]["uptime"] - requested,
                    "maximumObservedGapSeconds": max(gaps, default=0)}
    return None


def assess_startup(samples, analysis, control, token):
    if not isinstance(token, str) or not re.fullmatch(r"[0-9]{6}", token):
        raise CaptureError("invalidFixtureCue")
    # Passing control events alone never establish image or sound.
    output = assess_samples(samples, analysis, control, "hlsSubtitles")
    try:
        result = control["results"][0]
        if result.get("profile") != "controls":
            raise CaptureError("unsupportedTimingProfile")
        requested = request_time(result)
        began = result["startedAtUptime"]
        if any(not finite(event.get("seconds")) or not 0 <= event["seconds"] <= result["elapsedSeconds"]
               for event in result["events"]):
            raise CaptureError("invalidStartupEvents")
        first_receiver = next(e for e in result["events"] if e.get("kind") == "playing" and e.get("origin") == "receiver")
        if requested > began + first_receiver["seconds"]:
            raise CaptureError("playTimestampAfterReceiver")
        # A picture appearing only after a seek is not initial playback output.
        terminal = [began + event["seconds"] for event in result["events"]
                    if event.get("kind") in {"paused", "seeked", "stopped", "ended", "error"}
                    and finite(event.get("seconds")) and began + event["seconds"] >= requested]
        deadline = min([began + result["elapsedSeconds"], *terminal])
        frames = {frame["frame"]: frame for frame in analysis}
        for frame in analysis:
            if (any(type(frame.get(key)) is not bool for key in ("anyCue", "expectedCue", "testPattern"))
                    or not finite(frame.get("centralDifference")) or frame["centralDifference"] < 0
                    or frame.get("cueTokens") not in ([], [token])
                    or frame["expectedCue"] != (frame["cueTokens"] == [token])
                    or (frame["expectedCue"] and not frame["anyCue"])):
                raise CaptureError("invalidTimingFrame")
        video, audio = [], []
        for row in samples["rows"]:
            if row["kind"] == "video":
                video.append(dict(row, **{k: v for k, v in frames[row["frame"]].items() if k != "frame"}))
            elif row["kind"] == "audio":
                if not finite(row.get("rmsDBFS")) or ("testToneHz" in row and not finite(row["testToneHz"])):
                    raise CaptureError("invalidTimingAudio")
                audio.append(row)
            else:
                raise CaptureError("invalidTimingSample")
        if len({row["frame"] for row in video}) != len(video):
            raise CaptureError("duplicateTimingFrame")
        previous_video = [row for row in video if requested - 1.5 <= row["uptime"] < requested]
        previous_audio = [row for row in audio if requested - 1.5 <= row["uptime"] < requested]
        gaps = []
        if output["outcome"] != OUTPUT_PASS:
            gaps.append("playbackOutputNotEstablished")
        if any(row["expectedCue"] for row in video if row["uptime"] < requested):
            gaps.append("fixtureCueAlreadyPresentBeforePlay")
        if (not previous_video or requested - previous_video[-1]["uptime"] > 1
                or any(row["testPattern"] or row["anyCue"] for row in previous_video)):
            gaps.append("missingCleanVideoPreroll")
        if (len(previous_audio) < 2 or previous_audio[-1]["uptime"] - previous_audio[0]["uptime"] < .15
                or requested - previous_audio[-1]["uptime"] > .5
                or any(row["rmsDBFS"] > -60 for row in previous_audio)
                or any(b["uptime"] - a["uptime"] > .6 for a, b in zip(previous_audio, previous_audio[1:]))):
            gaps.append("missingSilentAudioPreroll")
        picture = onset(video, lambda r: r["expectedCue"] and r["testPattern"] and r["centralDifference"] > 1,
                        requested, deadline, 2, 1.25)
        sound = onset(audio, lambda r: r["rmsDBFS"] > -60 and abs(r.get("testToneHz", 0) - 880) < 35,
                      requested, deadline, 3, .6)
        if picture is None:
            gaps.append("freshMovingFixtureNotObservedBeforeControls")
        elif picture["maximumObservedGapSeconds"] > 1.5:
            gaps.append("videoSamplingGapAtStartup")
        if sound is None:
            gaps.append("fixtureAudioNotObservedBeforeControls")
        elif sound["maximumObservedGapSeconds"] > .75:
            gaps.append("audioSamplingGapAtStartup")
        # Do not expose apparently valid latency figures when attribution failed.
        return {"schemaVersion": 1, "outcome": "sampled_startup_observed" if not gaps else "inconclusive",
                "gaps": gaps, "picture": picture if not gaps else None, "audio": sound if not gaps else None,
                "scope": "first_captured_fresh_subtitle_picture_and_880Hz_audio_after_play",
                "limits": ["Callback timestamps include capture transport, scheduling and PNG persistence overhead.",
                           "Fresh-picture recognition includes subtitle display and OCR detection, not decoder first frame.",
                           "Observed sampling gaps are not error bounds on physical display or speaker latency.",
                           "Missing audio samples do not establish silence; receiver confirmation does not establish output."]}
    except (KeyError, TypeError, ValueError, IndexError, StopIteration, AttributeError):
        raise CaptureError("invalidStartupTimingEvidence") from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case_directory", type=Path)
    parser.add_argument("--cue-token", required=True, help="The fresh six-digit identifier in this generated fixture's cues")
    parser.add_argument("--output", required=True, type=Path, help="A new report path; existing evidence is never overwritten")
    args = parser.parse_args()
    paths = {"samples": args.case_directory / "capture/samples.json",
             "analysis": args.case_directory / "frame-analysis.json", "control": args.case_directory / "controls.json"}
    try:
        evidence = {name: read_evidence(path) for name, path in paths.items()}
        hashes = {name: pair[1] for name, pair in evidence.items()}
        inputs = {name: pair[0] for name, pair in evidence.items()}
        report = assess_startup(**inputs, token=args.cue_token)
        if any(read_evidence(path)[1] != hashes[name] for name, path in paths.items()):
            raise CaptureError("evidenceChangedDuringRead")
        report["inputSHA256"] = hashes
        report["evaluatorSHA256"] = fingerprint(Path(__file__))
        report["evaluatorDependenciesSHA256"] = {
            "playback_capture.py": fingerprint(Path(__file__).with_name("playback_capture.py"))}
        save_json(args.output, report)
        print(report["outcome"])
        return 0 if report["outcome"] == "sampled_startup_observed" else 1
    except (CaptureError, OSError, ValueError):
        print("Startup evidence is invalid or unavailable; no capture or playback was started.")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

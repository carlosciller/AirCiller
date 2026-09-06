"""Bounded, opt-in Apple TV capture workflow. Never imported by the daily app."""
import array
import hashlib
import json
import math
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import threading
import time

from playback_checks import finish_process_group

BASIC_CASES = ("directHDR", "hlsSubtitles", "hlsNoSubtitles")
CONTROL_CASES = (*BASIC_CASES, "hlsHDRNoSubtitles")
CASE_INFO = {
    "directHDR": ("controls", "directHDR"), "hlsSubtitles": ("controls", "hls"),
    "hlsNoSubtitles": ("controls", "hls"), "directTrackChanges": ("trackChanges", "directHDR"),
    "hlsTrackChanges": ("trackChanges", "hls"), "cancelPreparation": ("cancelPreparation", "hls"),
    "playlistTransition": ("playlistTransition", "directHDR"),
    "directLongPause": ("longPause", "directHDR"), "hlsLongPause": ("longPause", "hls"),
    "hlsHDRNoSubtitles": ("controls", "hlsHDR"),
}
CASES = tuple(CASE_INFO)
CONTROL_PASS = "automated_checks_passed_output_unverified"
OUTPUT_PASS = "sampled_output_observed"
CANCELLATION_PASS = "preparation_cancellation_observed"
LIMITS = ["Physical speakers and Atmos layout", "Physical HDR rendering", "Whole-movie reliability",
          "Frame-accurate subtitle timing", "Physical remote operation"]
MOVIE_EXTENSIONS = {".mp4", ".m4v", ".mov", ".mkv", ".ts", ".mts", ".m2ts"}


class CaptureError(Exception):
    """Only stable codes, never raw device, media, credential or OS messages."""


def label(value, maximum=256):
    return isinstance(value, str) and 0 < len(value.encode()) <= maximum and all(ord(c) >= 32 and ord(c) != 127 for c in value)


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def read_json(path, maximum=2_000_000):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > maximum:
        raise CaptureError("invalidReport")
    try:
        return json.loads(path.read_text(), parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
    except (ValueError, UnicodeError):
        raise CaptureError("invalidReport") from None


def save_json(path, value):
    # New run directories own every output; never replace an earlier report.
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as output:
        json.dump(value, output, indent=2, sort_keys=True, allow_nan=False)
        output.write("\n")


def fingerprint(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1_048_576), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_config(config):
    allowed = {"version", "deviceID", "captureSource", "hdrFixture", "fixtureEncoder", "cases", "fixtureOverrides"}
    if not isinstance(config, dict) or set(config) - allowed or type(config.get("version")) is not int or config["version"] != 1:
        raise CaptureError("invalidCaptureConfiguration")
    source = config.get("captureSource")
    if (not label(config.get("deviceID")) or not isinstance(source, dict)
            or set(source) != {"uniqueID", "name", "approvedAppleTV"}
            or source.get("approvedAppleTV") is not True
            or not label(source.get("uniqueID")) or not label(source.get("name"))):
        raise CaptureError("unapprovedCaptureSource")
    cases = config.get("cases", list(BASIC_CASES))
    if (not isinstance(cases, list) or not 1 <= len(cases) <= len(CASES)
            or any(not isinstance(case, str) or case not in CASES for case in cases) or len(set(cases)) != len(cases)):
        raise CaptureError("invalidCaptureCases")
    overrides = config.get("fixtureOverrides", {})
    if not isinstance(overrides, dict) or any(c not in CONTROL_CASES or c not in cases for c in overrides):
        raise CaptureError("invalidFixtureOverrides")
    for value in overrides.values():
        validate_movie_path(value)
    generated_cases = [case for case in cases if case not in overrides]
    for key, needed in [("hdrFixture", needs_hdr(generated_cases)), ("fixtureEncoder", needs_hls(generated_cases))]:
        value = config.get(key)
        if not needed and value is None:
            continue
        if not label(value, 4096) or not Path(value).is_absolute() or not Path(value).is_file():
            raise CaptureError("missingFixtureInput")
        if key == "hdrFixture":
            validate_movie_path(value)
        if key == "fixtureEncoder" and not os.access(value, os.X_OK):
            raise CaptureError("fixtureEncoderUnavailable")
    return cases


def validate_movie_path(value):
    if (not label(value, 4096) or not Path(value).is_absolute() or Path(value).is_symlink()
            or not Path(value).is_file() or Path(value).suffix.lower() not in MOVIE_EXTENSIONS
            or not 0 < Path(value).stat().st_size <= 2 * 1024**3):
        raise CaptureError("invalidFixtureInput")


def needs_hdr(cases):
    return any(CASE_INFO[c][1] in {"directHDR", "hlsHDR"} for c in cases)


def needs_hls(cases):
    return any(CASE_INFO[c][1] == "hls" or c == "playlistTransition" for c in cases)


class PipePump:
    def __init__(self, pipe, limit):
        self.data = bytearray()
        self.lock = threading.Lock()
        self.overflow = threading.Event()
        self.thread = threading.Thread(target=self._read, args=(pipe, limit), daemon=True)
        self.thread.start()

    def _read(self, pipe, limit):
        try:
            while True:
                block = pipe.read1(4096)
                if not block:
                    break
                with self.lock:
                    remaining = limit - len(self.data)
                    self.data.extend(block[:remaining])
                    if len(block) > remaining:
                        self.overflow.set()
                        break
        finally:
            pipe.close()

    def snapshot(self):
        with self.lock:
            return bytes(self.data)


def start_process(command, limit=1_000_000):
    process = subprocess.Popen([str(arg) for arg in command], start_new_session=True,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return process, PipePump(process.stdout, limit)


def bounded_command(command, timeout=30, limit=1_000_000):
    process, pump = start_process(command, limit)
    deadline = time.monotonic() + timeout
    try:
        while process.poll() is None:
            if pump.overflow.is_set():
                raise CaptureError("processOutputLimit")
            if time.monotonic() >= deadline:
                raise CaptureError("processTimeout")
            time.sleep(0.02)
        pump.thread.join(timeout=1)
        if pump.overflow.is_set():
            raise CaptureError("processOutputLimit")
        if pump.thread.is_alive():
            raise CaptureError("processOutputIncomplete")
        if process.returncode != 0:
            raise CaptureError("processFailed")
        return pump.snapshot()
    finally:
        finish_process_group(process)


def probe_fixture(path, ffmpeg, ffprobe, hdr):
    try:
        local_input = ["-protocol_whitelist", "file,pipe", "-format_whitelist", "mov,matroska,mpegts"]
        probe = json.loads(bounded_command([ffprobe, "-v", "error", *local_input, "-show_streams", "-show_format",
                                           "-show_entries", "program=program_id", "-of", "json", path]))
        duration = float(probe["format"]["duration"])
        if probe["format"].get("format_name") == "mpegts" and len(probe.get("programs", [])) > 1:
            raise CaptureError("unsupportedFixturePrograms")
        videos = [s for s in probe["streams"] if s.get("codec_type") == "video" and not s.get("disposition", {}).get("attached_pic")]
        audio = [s for s in probe["streams"] if s.get("codec_type") == "audio"]
        video = videos[0]
        is_hdr = video.get("color_transfer") in {"smpte2084", "arib-std-b67"} or any(
            "DOVI" in side.get("side_data_type", "") for side in video.get("side_data_list", []))
        if not math.isfinite(duration) or not 45 <= duration <= 180 or video.get("codec_name") not in {"h264", "hevc"} or is_hdr != hdr or not audio:
            raise CaptureError("unsupportedFixture")
        selected = next((a for a in audio if a.get("disposition", {}).get("default")), audio[0])
        if selected.get("codec_name") not in {"aac", "ac3", "eac3"} or selected.get("channels", 0) < 2:
            raise CaptureError("unsupportedFixtureAudio")
        # Check the intervals used by the control test, including its 15-second seek.
        for start in (1, 15):
            raw = bounded_command([ffmpeg, "-v", "error", *local_input, "-ss", str(start), "-i", path, "-t", "3",
                                   "-map", f"0:{selected['index']}", "-vn", "-ac", "1", "-ar", "8000", "-f", "f32le", "pipe:1"])
            values = array.array("f", raw)
            if not values or any(not math.isfinite(v) for v in values):
                raise CaptureError("fixtureAudioUnavailable")
            power = sum(float(v) * float(v) for v in values) / len(values)
            if power <= 10 ** (-65 / 10):
                raise CaptureError("fixtureHasSilentTestInterval")
        return {"sha256": fingerprint(path), "duration": duration, "videoCodec": video["codec_name"], "audioCodec": selected["codec_name"]}
    except (ValueError, KeyError, IndexError, TypeError):
        raise CaptureError("unsupportedFixture") from None


def prepare_fixtures(config, cases, project, directory):
    engine = project / ".build/AirCiller Playback Checks.app/Contents/Resources/Engine/ffmpeg/bin"
    ffmpeg, ffprobe = engine / "ffmpeg", engine / "ffprobe"
    fixtures = {}
    overrides = config.get("fixtureOverrides", {})
    cases = [case for case in cases if case not in overrides]
    for name, value in overrides.items():
        path = Path(value).resolve()
        fixtures[name] = (path, probe_fixture(path, ffmpeg, ffprobe, hdr=CASE_INFO[name][1] != "hls"))
    if needs_hdr(cases):
        path = Path(config["hdrFixture"]).resolve()
        fixtures["directHDR"] = (path, probe_fixture(path, ffmpeg, ffprobe, hdr=True))
        if "hlsHDRNoSubtitles" in cases:
            fixtures["hlsHDR"] = fixtures["directHDR"]
    if needs_hls(cases):
        # Explicit development encoder only generates a synthetic fixture. The
        # application and all probes continue to use the pinned bundled engine.
        encoder = Path(config["fixtureEncoder"]).resolve()
        path = directory / "synthetic-av.mkv"
        dual_audio = "hlsTrackChanges" in cases
        extra_input = ["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000"] if dual_audio else []
        extra_map = ["-map", "2:a:0"] if dual_audio else []
        extra_metadata = ["-disposition:a:0", "default", "-disposition:a:1", "0", "-metadata:s:a:1", "language=spa"] if dual_audio else []
        bounded_command([encoder, "-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=24",
                         "-f", "lavfi", "-i", "sine=frequency=880:sample_rate=48000", *extra_input, "-t", "60",
                         "-map", "0:v:0", "-map", "1:a:0", *extra_map, "-c:v", "libx264", "-preset", "veryfast", "-crf", "22",
                         "-g", "48", "-pix_fmt", "yuv420p", "-c:a", "eac3", "-b:a", "192k", "-ac", "2",
                         "-metadata:s:a:0", "language=eng", *extra_metadata, "-fs", "100000000", path], timeout=90)
        fixtures["hls"] = (path, probe_fixture(path, ffmpeg, ffprobe, hdr=False))
        fixtures["hls"][1]["generatorSHA256"] = fingerprint(encoder)
    return fixtures


def write_cues(path, token):
    cues = []
    for i, (start, end) in enumerate([(0, 10), (10, 20), (20, 30), (30, 45), (45, 60)], 1):
        def timestamp(seconds):
            return f"00:{seconds // 60:02d}:{seconds % 60:02d},000"
        cues.append(f"{i}\n{timestamp(start)} --> {timestamp(end)}\nAirCiller subtitle check: {token}-{i}\n")
    with path.open("x") as output:
        output.write("\n".join(cues))


def supervise_case(app_command, capture_command, ready, stop, timeout=180, ready_timeout=20):
    """Own both process groups. A dead capture cannot leave playback running."""
    app, app_output = start_process(app_command)
    capture = None
    deadline = time.monotonic() + timeout
    capture_deadline = None
    try:
        while app.poll() is None:
            if app_output.overflow.is_set() or time.monotonic() >= deadline:
                raise CaptureError("controlDeadlineOrOutputLimit")
            if capture is None and b"Checking: awaiting_capture_ready\n" in app_output.snapshot():
                capture, capture_output = start_process(capture_command, 4096)
                capture_deadline = time.monotonic() + ready_timeout
            if capture is not None:
                if "--long-pause" in capture_command:
                    marker = stop.with_name("capture.sampling-paused")
                    output = app_output.snapshot()
                    if b"Checking: resume_after_long_pause\n" in output:
                        marker.unlink(missing_ok=True)
                    elif b"Checking: hold_long_pause\n" in output:
                        marker.touch(mode=0o600, exist_ok=True)
                if capture.poll() is not None or capture_output.overflow.is_set():
                    raise CaptureError("captureLost")
                if not ready.exists() and time.monotonic() >= capture_deadline:
                    raise CaptureError("captureNotReady")
            time.sleep(0.03)
        if capture is None:
            raise CaptureError("controlsBlockedBeforeCapture")
        stop.touch(exist_ok=False)
        try:
            capture.wait(timeout=8)
        except subprocess.TimeoutExpired:
            raise CaptureError("captureCleanupTimeout") from None
        if capture.returncode != 0:
            raise CaptureError("captureIncomplete")
        if app.returncode != 0:
            raise CaptureError("controlRunFailed")
        if finish_process_group(app) or finish_process_group(capture):
            raise CaptureError("leftoverProcesses")
    finally:
        for process in (capture, app):
            if process is not None:
                finish_process_group(process)


def assess_samples(samples, analysis, control, case_name):
    try:
        if (not isinstance(samples, dict) or not isinstance(control, dict) or case_name not in CONTROL_CASES
                or type(samples.get("schemaVersion")) is not int or samples["schemaVersion"] != 1
                or samples.get("sourceVerified") is not True
                or samples.get("complete") is not True or control.get("outcome") != CONTROL_PASS):
            raise CaptureError("incompleteEvidence")
        results = control["results"]
        if (not isinstance(results, list) or len(results) != 1 or not isinstance(results[0], dict)
                or results[0].get("cleanupConfirmed") is not True or results[0].get("unverifiedChecks")):
            raise CaptureError("incompleteControlEvidence")
        result = results[0]
        subtitles_expected = case_name not in {"hlsNoSubtitles", "hlsHDRNoSubtitles"}
        if (result.get("route") != CASE_INFO[case_name][1]
                or result.get("subtitlesRequested") is not subtitles_expected):
            raise CaptureError("wrongControlCase")
        began = result["startedAtUptime"]
        duration = result["elapsedSeconds"]
        if not isinstance(result["events"], list) or any(not isinstance(e, dict) for e in result["events"]):
            raise CaptureError("invalidControlEvents")
        first = next(e for e in result["events"] if e.get("kind") == "playing" and e.get("origin") == "receiver")
        if not all(finite(v) and v >= 0 for v in (began, duration, first["seconds"])) or duration > 180:
            raise CaptureError("invalidCaptureTiming")
        start, end = began + first["seconds"] + 0.5, began + duration - 0.5
        if end <= start:
            raise CaptureError("invalidCaptureTiming")
        rows = samples["rows"]
        if not isinstance(rows, list) or not 1 <= len(rows) <= 1024 or not isinstance(analysis, list) or len(analysis) > 240:
            raise CaptureError("captureEvidenceLimit")
        if any(not isinstance(r, dict) for r in rows + analysis):
            raise CaptureError("invalidCaptureEvidence")
        if any(not finite(r.get("uptime")) for r in rows) or any(a["uptime"] > b["uptime"] for a, b in zip(rows, rows[1:])):
            raise CaptureError("invalidCaptureTiming")
        frames = {r["frame"]: r for r in analysis}
        if len(frames) != len(analysis):
            raise CaptureError("duplicateCaptureFrame")
        selected = [r for r in rows if r["kind"] == "video" and start <= r["uptime"] <= end]
        audio = [r for r in rows if r["kind"] == "audio" and start <= r["uptime"] <= end]
        inspected = [frames[r["frame"]] for r in selected]
        if (len(selected) < 6 or selected[-1]["uptime"] - selected[0]["uptime"] < 2
                or len({r["frame"] for r in selected}) != len(selected)):
            raise CaptureError("insufficientCapturedFrames")
        if selected[0]["uptime"] > start + 1.5 or selected[-1]["uptime"] < end - 1.5:
            raise CaptureError("captureDoesNotCoverPlayback")
        if any(type(r[k]) is not bool for r in inspected for k in ("anyCue", "expectedCue", "testPattern")):
            raise CaptureError("invalidFrameAnalysis")
        if any(not finite(r.get("centralDifference")) or r["centralDifference"] < 0 for r in inspected):
            raise CaptureError("invalidFrameAnalysis")
        if any(not finite(r.get("rmsDBFS")) for r in audio):
            raise CaptureError("invalidAudioAnalysis")
        cues = sum(r["expectedCue"] for r in inspected)
        any_cues = sum(r["anyCue"] for r in inspected)
        moving = sum(r["centralDifference"] > 1 for r in inspected)
        active_audio = sum(r["rmsDBFS"] > -60 for r in audio)
        patterns = sum(r["testPattern"] for r in inspected)
        gaps = []
        if moving < 2: gaps.append("movingPictureNotObserved")
        if len(audio) < 6 or active_audio < 5: gaps.append("audioNotObserved")
        elif audio[0]["uptime"] > start + 1.5 or audio[-1]["uptime"] < end - 1.5:
            gaps.append("audioDoesNotCoverPlayback")
        if case_name != "directHDR" and patterns < 3: gaps.append("expectedPictureNotObserved")
        if not subtitles_expected:
            if any_cues: gaps.append("unexpectedSubtitles")
        elif cues < 3:
            gaps.append("expectedSubtitleCueNotObserved")
        return {"outcome": OUTPUT_PASS if not gaps else "inconclusive", "gaps": gaps,
                "frames": len(inspected), "framesWithExpectedCue": cues, "framesWithAnyCue": any_cues,
                "framesWithCentralChange": moving, "framesWithTestPattern": patterns,
                "audioMeasurements": len(audio), "nonSilentAudioMeasurements": active_audio}
    except (KeyError, TypeError, ValueError, IndexError, StopIteration):
        raise CaptureError("invalidCaptureEvidence") from None


def run_case(name, config, fixture, project, directory, candidate_hash):
    directory.mkdir(mode=0o700)
    capture_dir = directory / "capture"
    capture_dir.mkdir(mode=0o700)
    ready, stop = directory / "capture.ready", directory / "capture.stop"
    token = f"{secrets.randbelow(1_000_000):06d}"
    clip = {"path": str(fixture[0]), "route": CASE_INFO[name][1]}
    if name not in {"hlsNoSubtitles", "hlsHDRNoSubtitles"}:
        subtitle = directory / "cue.eng.srt"
        write_cues(subtitle, token)
        clip["externalSubtitle"] = str(subtitle)
    plan = directory / "plan.json"
    save_json(plan, {"version": 1, "deviceID": config["deviceID"], "captureReadyFile": str(ready), "clips": [clip]})
    binary = project / ".build/AirCiller Playback Checks.app/Contents/MacOS/AirCiller"
    controls_path = directory / "controls.json"
    tools_dir = project / ".build/playback-capture-tools"
    source = config["captureSource"]
    result = {"case": name, "fixture": fixture[1], "outcome": "inconclusive"}
    try:
        supervise_case([binary, "--run", plan, "--report", controls_path, "--tv-is-idle"],
                       [tools_dir / "capture-samples", "--capture", source["uniqueID"], source["name"], capture_dir, ready, stop], ready, stop)
        controls = read_json(controls_path)
        samples = read_json(capture_dir / "samples.json")
        analysis = json.loads(bounded_command([tools_dir / "analyze-frames", capture_dir, token], timeout=90))
        save_json(directory / "frame-analysis.json", analysis)
        result.update(assess_samples(samples, analysis, controls, name))
        if fingerprint(binary) != candidate_hash:
            raise CaptureError("candidateChangedDuringRun")
        result["controls"] = controls["outcome"]
        result["sampleManifestSHA256"] = fingerprint(capture_dir / "samples.json")
    except CaptureError as error:
        result.update(outcome="inconclusive", gaps=[str(error)])
    return result


def run_workflow(config_path, project, *, run=False, prepare=False):
    config = read_json(config_path, maximum=65_536)
    cases = validate_config(config)
    if not run and not prepare:
        print("Capture configuration validated. No discovery, Keychain, capture or playback was started.")
        return 0
    root = project / ".build/playback-checks"
    root.mkdir(exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix="capture-run-", dir=root))
    report = {"schemaVersion": 1, "outcome": "incomplete", "cases": [], "limits": LIMITS}
    binary = project / ".build/AirCiller Playback Checks.app/Contents/MacOS/AirCiller"
    try:
        if not binary.is_file(): raise CaptureError("checkAppNotBuilt")
        report["candidateSHA256"] = fingerprint(binary)
        if run:
            print("Checking noninteractive credential access...", flush=True)
            try:
                bounded_command([binary, "--check-keychain", config["deviceID"]], timeout=15)
            except CaptureError:
                raise CaptureError("credentialAccessUnavailable") from None
            bounded_command(["/bin/zsh", project / "Scripts/build_playback_capture.sh"], timeout=90)
            report["captureToolsSHA256"] = {
                name: fingerprint(project / ".build/playback-capture-tools" / name)
                for name in ("capture-samples", "analyze-frames")
            }
            source = config["captureSource"]
            try:
                bounded_command([project / ".build/playback-capture-tools/capture-samples", "--inspect-source",
                                 source["uniqueID"], source["name"]], timeout=15)
            except CaptureError:
                raise CaptureError("captureSourceUnavailable") from None
        print("Preparing and validating audible fixtures...", flush=True)
        fixtures = prepare_fixtures(config, cases, project, directory)
        if not run:
            report.update(outcome="fixtures_prepared", fixtures={k: v[1] for k, v in fixtures.items()})
        else:
            for index, name in enumerate(cases, 1):
                print(f"Case {index}/{len(cases)}: {name}", flush=True)
                if name in CONTROL_CASES:
                    fixture = fixtures[name] if name in config.get("fixtureOverrides", {}) else fixtures[CASE_INFO[name][1]]
                    result = run_case(name, config, fixture,
                                      project, directory / f"case-{index:02d}", report["candidateSHA256"])
                else:
                    from playback_scenarios import run_scenario
                    result = run_scenario(name, config, fixtures, project, directory / f"case-{index:02d}", report["candidateSHA256"])
                report["cases"].append(result)
                print(f"Case {index}: {result['outcome']}", flush=True)
                if result["outcome"] not in {OUTPUT_PASS, CANCELLATION_PASS}:
                    break
            passed = len(report["cases"]) == len(cases) and all(c["outcome"] in {OUTPUT_PASS, CANCELLATION_PASS} for c in report["cases"])
            report["outcome"] = ("selected_checks_passed" if "cancelPreparation" in cases else OUTPUT_PASS) if passed else "inconclusive"
    except CaptureError as error:
        report.update(outcome="blocked", failure=str(error))
    except KeyboardInterrupt:
        report.update(outcome="incomplete", failure="interrupted")
    except (OSError, ValueError, TypeError):
        report.update(outcome="incomplete", failure="localWorkflowFailure")
    finally:
        save_json(directory / "report.json", report)
        print(f"{report['outcome']}: {directory / 'report.json'}", flush=True)
    return 0 if report["outcome"] in {OUTPUT_PASS, "selected_checks_passed", "fixtures_prepared"} else 1

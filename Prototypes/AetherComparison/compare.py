"""Isolated original-stream comparison. No receiver, credentials or installed app access."""
import hashlib
import array
import math
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
from trim_metadata import correct_audio_edit, audio_track_id, final_audio_duration_field
import struct

sys.dont_write_bytecode = True
PROJECT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT / "Scripts"))
import test_storage

ENGINE = PROJECT / ".build/dependencies/AirCillerEngine-ffmpeg-9.0.1-python-3.13.15/ffmpeg/bin"
AETHER = PROJECT / ".build/dependencies/AetherEngine-7.62.0"
PIN = "a1d2cab8281cbf06f5f459b05dad4653ad12559f"


def run(args, timeout=90):
    return subprocess.run([str(x) for x in args], check=True, capture_output=True, timeout=timeout).stdout


def pcm_difference(reference, actual):
    common = min(len(reference), len(actual))
    differences = [i for i in range(common) if reference[i] != actual[i]]
    return {"identical": reference == actual,
            "referenceSamples": len(reference), "actualSamples": len(actual),
            "differentSamplesInOverlap": len(differences),
            "firstDifference": differences[0] if differences else None,
            "lastDifference": differences[-1] if differences else None}


class Snapshot:
    """Snapshot bounded same-origin HTTP resources. Refuse unfinished VOD."""
    def __init__(self, url, directory):
        self.origin = urllib.parse.urlsplit(url)
        if self.origin.scheme != "http" or self.origin.hostname != "127.0.0.1":
            raise ValueError("Not a local engine URL")
        self.directory = directory
        self.saved = {}
        self.total = 0

    def fetch(self, url):
        if url in self.saved:
            return self.saved[url]
        parsed = urllib.parse.urlsplit(url)
        if (parsed.scheme, parsed.netloc) != (self.origin.scheme, self.origin.netloc):
            raise ValueError("Cross-origin engine resource")
        if len(self.saved) >= 256:
            raise ValueError("Resource budget")
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                raise ValueError("Unexpected redirect")
        opener = urllib.request.build_opener(NoRedirect)
        with opener.open(url, timeout=15) as response:
            if response.url != url:
                raise ValueError("Unexpected redirect")
            data = response.read(32 * 1024 * 1024 + 1)
        self.total += len(data)
        if len(data) > 32 * 1024 * 1024 or self.total > 256 * 1024 * 1024:
            raise ValueError("Byte budget")
        is_playlist = data.startswith(b"#EXTM3U")
        suffix = ".m3u8" if is_playlist else Path(parsed.path).suffix
        if suffix not in {".m3u8", ".m4s", ".mp4", ".vtt"}:
            raise ValueError("Unexpected resource type")
        name = f"resource-{len(self.saved):03d}{suffix}"
        self.saved[url] = name
        if is_playlist:
            text = data.decode()
            if "#EXTINF:" in text and "#EXT-X-ENDLIST" not in text:
                raise ValueError("Engine output is not complete VOD")
            lines = []
            for line in text.splitlines():
                if line.startswith("#"):
                    line = re.sub(r'URI="([^"]+)"', lambda m: 'URI="' + self.fetch(
                        urllib.parse.urljoin(url, m[1])) + '"', line)
                elif line.strip():
                    line = self.fetch(urllib.parse.urljoin(url, line.strip()))
                lines.append(line)
            data = ("\n".join(lines) + "\n").encode()
        (self.directory / name).write_bytes(data)
        return name


def campaign():
    codec = sys.argv[2] if len(sys.argv) > 2 else "aac"
    if codec not in {"aac", "eac3"}:
        raise ValueError("Fixture codec must be aac or eac3")
    if run(["git", "-C", AETHER, "rev-parse", "HEAD"]).decode().strip() != PIN:
        raise ValueError("Aether revision changed")
    root = Path(tempfile.mkdtemp(prefix="run.", dir=PROJECT / ".build/performance"))
    test_storage.register_run(PROJECT, root)
    print(f"Report directory: {root}", flush=True)
    report = {"aetherRevision": PIN, "scope": "Local synthetic original-stream prototype; no Apple TV"}
    report["fixtureAudioCodec"] = codec
    report["prerollExperiment"] = os.environ.get("AIRCILLER_PREROLL_PROBE") == "1"
    try:
        source = root / "source.mkv"
        cue = root / "cue.eng.srt"
        cue.write_text("1\n00:00:00,000 --> 00:00:27,000\nAirCiller Aether comparison 726491\n")
        generator = Path(sys.argv[1]).resolve(strict=True)
        run([generator, "-v", "error", "-nostdin", "-f", "lavfi", "-i", "testsrc2=duration=27:size=1280x720:rate=24",
             "-f", "lavfi", "-i", "sine=frequency=880:sample_rate=48000", "-i", cue,
             "-t", "27", "-map", "0:v", "-map", "1:a", "-map", "2:s", "-c:v", "libx264",
             "-preset", "ultrafast", "-g", "48", "-crf", "22", "-c:a", codec, "-c:s", "srt",
             "-metadata:s:s:0", "language=eng", source])
        source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
        report["sourceSHA256"] = source_hash
        out = root / "aether"
        out.mkdir()
        host = AETHER / ".build/out/Products/Release/AirCillerAetherProbe"
        stop = root / "host.stop"
        host_report = root / "host.json"
        began = time.monotonic()
        with (root / "aether.log").open("wb") as log:
            process = subprocess.Popen([str(host), str(source), str(host_report), str(stop)],
                                       stdout=log, stderr=log, start_new_session=True)
            try:
                deadline = time.monotonic() + 60
                while not host_report.exists() and time.monotonic() < deadline and process.poll() is None:
                    time.sleep(.1)
                if not host_report.exists():
                    raise RuntimeError("Aether host did not become ready")
                state = json.loads(host_report.read_text())
                report["aetherHost"] = {k: v for k, v in state.items() if k != "url"}
                if state["status"] != "local-session-ready":
                    raise RuntimeError("Aether refused the native original-stream session")
                snapshot = Snapshot(state["url"], out)
                entry = snapshot.fetch(state["url"])
                report["aetherSnapshotSeconds"] = time.monotonic() - began
                report["aetherEntry"] = entry
                report["aetherBytes"] = snapshot.total
            finally:
                stop.touch()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=3)
                report["aetherProcessExited"] = process.poll() is not None
        # Existing production preparation services, no application UI or settings.
        if os.environ.get("AIRCILLER_EXACT_EDIT_PROBE") == "1":
            metadata = json.loads(run([ENGINE / "ffprobe", "-v", "error", "-select_streams", "a:0",
                "-show_packets", "-show_streams", "-of", "json", source]))
            first = metadata["packets"][0]
            skip = next(s["skip_samples"] for s in first["side_data_list"] if s["side_data_type"] == "Skip Samples")
            rate = int(metadata["streams"][0]["sample_rate"])
            frames = json.loads(run([ENGINE / "ffprobe", "-v", "error", "-select_streams", "a:0",
                "-show_frames", "-show_entries", "frame=nb_samples", "-of", "json", source]))
            presented = sum(int(f["nb_samples"]) for f in frames["frames"])
            edits = []
            for init in out.glob("*.mp4"):
                corrected, changes = correct_audio_edit(init.read_bytes(), skip, rate, presented)
                if changes:
                    init.write_bytes(corrected)
                    edits.extend(changes)
            if len(edits) != 1:
                raise ValueError("Expected exactly one corrected audio init edit")
            report["exactPresentationEdits"] = edits
            if codec == "eac3" and os.environ.get("AIRCILLER_TAIL_DURATION_PROBE") == "1":
                playlist = next(p for p in out.glob("*.m3u8") if "#EXT-X-MAP:" in p.read_text())
                lines = playlist.read_text().splitlines()
                init_name = re.search(r'URI="([^"]+)"', next(l for l in lines if l.startswith("#EXT-X-MAP:")))[1]
                tail = out / [l for l in lines if l and not l.startswith("#")][-1]
                data = bytearray(tail.read_bytes())
                track = audio_track_id((out / init_name).read_bytes())
                pos, old = final_audio_duration_field(data, track)
                padding = next(s["discard_padding"] for s in metadata["packets"][-1]["side_data_list"] if s["side_data_type"] == "Skip Samples")
                full_samples = int(frames["frames"][-1]["nb_samples"]) + padding
                if not 0 < old <= full_samples or full_samples - old > rate // 100:
                    raise ValueError("Unexpected final block duration")
                struct.pack_into(">I", data, pos, full_samples)
                tail.write_bytes(data)
                report["tailDurationRepair"] = {"old": old, "fullSamples": full_samples, "discardPadding": padding}
            if os.environ.get("AIRCILLER_NATIVE_READ_PROBE") == "1":
                playlists = [p for p in out.glob("*.m3u8") if "#EXT-X-MAP:" in p.read_text()]
                if len(playlists) != 1:
                    raise ValueError("Expected one multiplexed media playlist")
                lines = playlists[0].read_text().splitlines()
                init_name = re.search(r'URI="([^"]+)"', next(l for l in lines if l.startswith("#EXT-X-MAP:")))[1]
                parts = [init_name] + [l for l in lines if l and not l.startswith("#")]
                flat = root / "native-read.mp4"
                flat.write_bytes(b"".join((out / p).read_bytes() for p in parts))
                try:
                    report["nativeAudioRead"] = json.loads(run([PROJECT / ".build/aether-read-audio", flat], timeout=45))
                    native_packets = json.loads(run([PROJECT / ".build/aether-read-audio", flat, "--packets"], timeout=45))
                    (root / "native-packets.json").write_text(json.dumps(native_packets, indent=2))
                    (root / "native-pcm.json").write_text(json.dumps(report["nativeAudioRead"], indent=2))
                    report["nativeAudioRead"].pop("buffers", None)
                    reference = root / "native-reference.mp4"
                    run([ENGINE / "ffmpeg", "-v", "error", "-i", source, "-map", "0:v:0", "-map", "0:a:0",
                        "-c", "copy", "-use_editlist", "1", "-avoid_negative_ts", "disabled", reference])
                    ref_data, ref_changes = correct_audio_edit(reference.read_bytes(), skip, rate, presented)
                    reference.write_bytes(ref_data)
                    native_reference = json.loads(run([PROJECT / ".build/aether-read-audio", reference], timeout=45))
                    (root / "native-reference.json").write_text(json.dumps(native_reference, indent=2))
                    native_reference.pop("buffers", None)
                    report["nativeReferenceRead"] = native_reference
                    ref_pcm = run([ENGINE / "ffmpeg", "-v", "error", "-i", reference, "-map", "0:a:0",
                        "-c:a", "pcm_f32le", "-f", "f32le", "-"])
                    source_pcm = run([ENGINE / "ffmpeg", "-v", "error", "-i", source, "-map", "0:a:0",
                        "-c:a", "pcm_f32le", "-f", "f32le", "-"])
                    report["referencePCMMatchesSource"] = ref_pcm == source_pcm
                    report["nativeReferenceBytesMatch"] = (native_reference["decodedBytesSHA256"] ==
                        report["nativeAudioRead"]["decodedBytesSHA256"] and native_reference["samples"] == report["nativeAudioRead"]["samples"])
                except subprocess.CalledProcessError as error:
                    report["nativeAudioRead"] = {"status": "failed", "exitCode": error.returncode,
                        "error": error.stderr.decode(errors="replace")[:1500]}
        baseline = root / "baseline"
        baseline.mkdir()
        tool = PROJECT / ".build/aether-comparison-baseline"
        run([tool, source, baseline, ENGINE / "ffmpeg", ENGINE / "ffprobe"])
        report["baseline"] = json.loads((baseline / "baseline.json").read_text())
        paths = {"source": source, "aether": out / entry, "airciller": baseline / "master.m3u8"}
        evidence = {}
        decoded_audio = {}
        for name, path in paths.items():
            options = ["-protocol_whitelist", "file,crypto,data"] if path.suffix == ".m3u8" else []
            probe = json.loads(run([ENGINE / "ffprobe", "-v", "error", *options, "-show_streams", "-show_format", "-of", "json", path]))
            hashes = run([ENGINE / "ffmpeg", "-v", "error", *options, "-i", path, "-map", "0:v:0",
                          "-fps_mode", "passthrough", "-f", "framemd5", "-"])
            decoded = [line.rsplit(b",", 1)[-1].strip().decode() for line in hashes.splitlines() if line and not line.startswith(b"#")]
            audio = json.loads(run([ENGINE / "ffprobe", "-v", "error", *options, "-select_streams", "a:0",
                                   "-show_packets", "-show_data_hash", "sha256", "-of", "json", path]))
            pcm = array.array("f", run([ENGINE / "ffmpeg", "-v", "error", *options, "-i", path,
                              "-map", "0:a:0", "-c:a", "pcm_f32le", "-f", "f32le", "-"]))
            head = pcm[:1024]
            decoded_audio[name] = pcm
            evidence[name] = {"videoFrames": decoded, "audioPackets": [r["data_hash"] for r in audio["packets"]],
                              "firstPackets": audio["packets"][:3],
                              "lastPackets": audio["packets"][-3:],
                              "audioStream": next(r for r in probe["streams"] if r["codec_type"] == "audio"),
                              "videoStart": next(r for r in probe["streams"] if r["codec_type"] == "video").get("start_time"),
                              "decodedSamples": len(pcm), "first1024Peak": max(map(abs, head)),
                              "first1024RMS": math.sqrt(sum(x*x for x in head) / len(head)),
                              "codecs": [r["codec_name"] for r in probe["streams"]]}
        report["videoPixelsIdentical"] = all(evidence[x]["videoFrames"] == evidence["source"]["videoFrames"] for x in ("aether", "airciller"))
        report["decodedAudioDifference"] = pcm_difference(decoded_audio["source"], decoded_audio["aether"])
        report["aetherDecodedAudioIdentical"] = report["decodedAudioDifference"]["identical"]
        report["audioPacketsIdentical"] = all(evidence[x]["audioPackets"] == evidence["source"]["audioPackets"] for x in ("aether", "airciller"))
        report["packetCounts"] = {name: len(data["audioPackets"]) for name, data in evidence.items()}
        report["nativeTextPresent"] = any("AirCiller Aether comparison 726491" in p.read_text() for p in out.glob("*.vtt"))
        report["sourceUnchanged"] = hashlib.sha256(source.read_bytes()).hexdigest() == source_hash
        (root / "stream-parity.json").write_text(json.dumps(evidence, indent=2))
        report["status"] = "local-comparison-passed" if all(report[k] for k in
            ("videoPixelsIdentical", "audioPacketsIdentical", "aetherDecodedAudioIdentical",
             "nativeTextPresent", "sourceUnchanged")) else "local-comparison-failed"
    except Exception as error:
        report["status"] = "blocked-or-failed"
        report["error"] = str(error)
    finally:
        (root / "report.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2), flush=True)
    return 0 if report["status"] == "local-comparison-passed" else 1


if __name__ == "__main__":
    sys.exit(test_storage.guarded(PROJECT, campaign))

"""Bounded real-service regression for adjusted SDR HLS; no receiver access."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from verify_stream_copy import coded_picture_digest

TIMESTAMP_TOLERANCE = .001 + 1e-9  # One Matroska clock tick, including float roundoff.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("runner", "engine", "source", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    source = args.source.resolve()
    if not source.is_file() or source.stat().st_size > 64 * 1024**2:
        raise ValueError("Use a bounded synthetic input")
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    ffmpeg, ffprobe = (args.engine.resolve() / name for name in ("ffmpeg", "ffprobe"))

    def run(command):
        return subprocess.check_output([str(value) for value in command], stderr=subprocess.PIPE, timeout=90)

    def packets(path, stream):
        return json.loads(run([ffprobe, "-v", "error", "-select_streams", stream, "-show_packets",
                               "-show_data_hash", "sha256", "-of", "json", path]))["packets"]

    def pictures(path):
        return coded_picture_digest(run([ffmpeg, "-v", "error", "-i", path, "-map", "0:v:0", "-c", "copy",
                                         "-bsf:v", "h264_mp4toannexb", "-f", "h264", "pipe:1"]), "h264")

    def joined(directory, kind):
        files = [directory / (kind + "-init.mp4")]
        pending_gap = False
        for line in (directory / (kind + ".m3u8")).read_text().splitlines():
            if line == "#EXT-X-GAP":
                pending_gap = True
            elif line and not line.startswith("#"):
                if Path(line).name != line:
                    raise ValueError("Unsafe fragment")
                if not pending_gap:
                    files.append(directory / line)
                pending_gap = False
        if sum(path.stat().st_size for path in files) > 64 * 1024**2:
            raise ValueError("Fixture exceeded limit")
        target = directory / ("qa-" + kind + ".mp4")
        with target.open("xb") as output:
            for path in files:
                output.write(path.read_bytes())
        return target

    original_video = packets(source, "v:0")
    original_audio = packets(source, "a:0")
    original_pictures = pictures(source)
    source_probe = json.loads(run([ffprobe, "-v", "error", "-show_format", "-show_streams", "-of", "json", source]))
    if not 59 <= float(source_probe["format"]["duration"]) <= 61:
        raise ValueError("Use a 60-second synthetic input")
    rows = []
    cache = args.output / "cache"
    for delay in (.05, -.05, .5, -.5, 5, -5):
        for warm in (False, True):
            directory = args.output / f"original-{delay:+g}-{'warm' if warm else 'cold'}"
            result = json.loads(run([args.runner.resolve(), source, directory.resolve(), args.engine.resolve(),
                                     delay, "original", cache.resolve()]))
            video_path, audio_path = joined(directory, "video"), joined(directory, "audio")
            video, audio = packets(video_path, "v:0"), packets(audio_path, "a:0")
            if len(video) != len(original_video) or len(audio) != len(original_audio):
                raise ValueError("Packet count changed")
            if pictures(video_path) != original_pictures:
                raise ValueError("Coded video changed")
            if [p["data_hash"] for p in audio] != [p["data_hash"] for p in original_audio]:
                raise ValueError("Encoded audio changed")
            video_shift = float(video[1]["pts_time"]) - float(original_video[1]["pts_time"])
            audio_shift = float(audio[0]["pts_time"]) - float(original_audio[0]["pts_time"])
            if abs(audio_shift - video_shift - delay) > TIMESTAMP_TOLERANCE:
                raise ValueError("Incorrect common-clock offset")
            for index, (before, after) in enumerate(zip(original_video, video)):
                hold = -delay if delay < 0 and index == 0 else 0
                for key in ("pts_time", "dts_time"):
                    if key in before and key in after and abs(float(after[key]) - float(before[key]) - video_shift + hold) > TIMESTAMP_TOLERANCE:
                        raise ValueError("Unexpected video timestamp change")
                if abs(float(after["duration_time"]) - float(before["duration_time"]) - hold) > TIMESTAMP_TOLERANCE:
                    raise ValueError("Unexpected video duration change")
            for before, after in zip(original_audio, audio):
                if abs(float(after["pts_time"]) - float(before["pts_time"]) - audio_shift) > TIMESTAMP_TOLERANCE:
                    raise ValueError("Audio samples moved inconsistently")
                if abs(float(after["duration_time"]) - float(before["duration_time"])) > TIMESTAMP_TOLERANCE:
                    raise ValueError("Audio duration changed")
            if result["used_cache"] is not warm:
                raise ValueError("Incorrect cache reuse")
            for kind in ("video", "audio"):
                total = sum(float(line[8:].rstrip(",")) for line in (directory / (kind + ".m3u8")).read_text().splitlines()
                            if line.startswith("#EXTINF:"))
                if abs(total - result["duration"]) > .001:
                    raise ValueError("Truncated rendition")
            row = {"delay": delay, "warm": warm, "result": result, "videoPackets": len(video),
                   "audioPackets": len(audio), "codedVideoSHA256": original_pictures[1],
                   "allAudioPayloadsRetained": True, "allPacketTimesVerified": True}
            rows.append(row)
            print(json.dumps(row), flush=True)
    for mode in ("compatible", "stereo"):
        for delay in (.5, -.5, 5, -5):
            directory = args.output / f"{mode}-{delay:+g}"
            result = json.loads(run([args.runner.resolve(), source, directory.resolve(), args.engine.resolve(), delay, mode]))
            if pictures(joined(directory, "video")) != original_pictures:
                raise ValueError("Explicit audio conversion changed video")
            audio = packets(joined(directory, "audio"), "a:0")
            span = max(float(p["pts_time"]) + float(p["duration_time"]) for p in audio) - min(float(p["pts_time"]) for p in audio)
            if abs(span - 60) > .1:
                raise ValueError("Converted audio was truncated")
            row = {"mode": mode, "delay": delay, "result": result, "audioSpan": span, "codedVideoRetained": True}
            rows.append(row)
            print(json.dumps(row), flush=True)
    if hashlib.sha256(source.read_bytes()).hexdigest() != source_hash:
        raise ValueError("Original input changed")
    report = {"sourceSHA256": source_hash, "sourceUnchanged": True, "receiverTested": False, "cases": rows}
    with (args.output / "report.json").open("x") as output:
        json.dump(report, output, indent=2)
        output.write("\n")


if __name__ == "__main__":
    main()

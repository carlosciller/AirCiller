"""Measure byte-identical, visible bitmap repetitions; no OCR or media playback.

Usage: script /absolute/movie stream-index canvas-width canvas-height
Canvas must be established from the subtitle source, not inferred from video.
"""
import collections
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
from benchmark_bitmap_preparation import PROJECT, ENGINE
import test_storage


def campaign():
    source = Path(sys.argv[1]).resolve(strict=True)
    index, width, height = map(int, sys.argv[2:5])
    if not 0 <= index <= 200 or not 1 <= width <= 4096 or not 1 <= height <= 2160:
        raise ValueError("Invalid stream or canvas")
    root = Path(tempfile.mkdtemp(prefix="run.", dir=PROJECT / ".build/performance"))
    test_storage.register_run(PROJECT, root)
    frames = root / "frames"
    frames.mkdir()
    result = subprocess.run([
        str(ENGINE / "ffmpeg"), "-hide_banner", "-nostdin", "-canvas_size", f"{width}x{height}",
        "-i", str(source), "-filter_complex",
        f"[0:{index}]split=2[bitmap][bounds];[bounds]alphaextract,bbox=min_val=1,nullsink",
        "-map", "[bitmap]", "-c:v", "png", "-compression_level", "6", "-pred", "none",
        "-fps_mode", "passthrough", "-frame_pts", "1", str(frames / "frame-%016d.png")],
        capture_output=True, timeout=180)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace")[-1000:])
    bounds = {int(m[0]): tuple(map(int, m[1:])) for m in re.findall(
        r"pts:(-?[0-9]+).*?x1:([0-9]+) x2:([0-9]+) y1:([0-9]+) y2:([0-9]+)",
        result.stderr.decode(errors="replace"))}
    keys = collections.Counter()
    previous = None
    for frame in sorted(frames.glob("*.png")):
        digest = hashlib.sha256(frame.read_bytes()).hexdigest()
        timestamp = int(frame.stem.removeprefix("frame-"))
        if digest != previous and timestamp in bounds:
            keys[(digest, bounds[timestamp])] += 1
        previous = digest
    report = {"visibleGroups": sum(keys.values()), "uniqueImageAndBounds": len(keys),
              "recognitionsAvoidable": sum(v - 1 for v in keys.values()),
              "scope": "Encoded PNG equality plus crop bounds; adjacent duplicate grouping retained; no OCR"}
    (root / "measurement.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    print(f"Report: {root / 'measurement.json'}")


if __name__ == "__main__":
    sys.exit(test_storage.guarded(PROJECT, lambda: campaign() or 0))

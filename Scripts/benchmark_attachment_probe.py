"""Compare the app's actual probe query with video-only codec extradata.

Usage: benchmark_attachment_probe.py /explicit/development/ffmpeg [attachment MiB]
The optional attachment size defaults to 24; use 0 for the no-attachment control.
"""
import json
from pathlib import Path
import re
import statistics
import sys
import tempfile
import time

sys.dont_write_bytecode = True
from benchmark_bitmap_preparation import ENGINE, PROJECT, run
import test_storage


def campaign():
    attachment_mib = int(sys.argv[2]) if len(sys.argv) > 2 else 24
    if not 0 <= attachment_mib <= 24:
        raise ValueError("Attachment size must be between 0 and 24 MiB")
    (PROJECT / ".build/performance").mkdir(exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix="run.", dir=PROJECT / ".build/performance"))
    test_storage.register_run(PROJECT, root)
    font = root / "attachment.bin"
    font.write_bytes(bytes(range(256)) * (attachment_mib * 1024 * 1024 // 256))
    source = root / "attached.mkv"
    entries = re.search(r'"(format=format_name[^"\n]+)"',
                        (PROJECT / "Sources/MediaProbeService.swift").read_text()).group(1)
    # Freeze the old query even when this benchmark is run after the correction.
    if ",extradata," not in entries:
        entries = entries.replace(",level,", ",level,extradata,")
    try:
        run([Path(sys.argv[1]).resolve(strict=True), "-v", "error", "-f", "lavfi", "-i",
             "testsrc2=duration=1:size=320x180:rate=24", "-c:v", "libx265", "-preset", "ultrafast",
             "-x265-params", "log-level=error",
             *(["-attach", font, "-metadata:s:t", "mimetype=application/x-truetype-font"]
               if attachment_mib else []), source])
    finally:
        font.unlink()
    rows = []
    for iteration in range(3):
        results = {}
        for mode in (["all", "video-only"] if iteration % 2 == 0 else ["video-only", "all"]):
            began = time.monotonic()
            raw = run([ENGINE / "ffprobe", "-v", "error", "-show_entries",
                       entries if mode == "all" else entries.replace(",extradata,", ","),
                       *(["-show_data"] if mode == "all" else []), "-of", "json", source])
            response = json.loads(raw)
            output_bytes = len(raw)
            if mode == "video-only":
                video = next(stream for stream in response["streams"] if stream["codec_type"] == "video")
                extra = run([ENGINE / "ffprobe", "-v", "error", "-select_streams", str(video["index"]),
                             "-show_entries", "stream=index,codec_name,extradata", "-show_data", "-of", "json", source])
                output_bytes += len(extra)
                video["extradata"] = json.loads(extra)["streams"][0]["extradata"]
            seconds = time.monotonic() - began
            # The app consumes extradata only for its selected HEVC video.
            for stream in response["streams"]:
                if stream["codec_type"] != "video":
                    stream.pop("extradata", None)
            results[mode] = response
            rows.append({"iteration": iteration, "mode": mode, "seconds": seconds, "stdoutBytes": output_bytes})
        if results["all"] != results["video-only"]:
            raise RuntimeError("Consumed probe metadata changed")
    report = {"samples": rows, "medianSeconds": {
        mode: statistics.median(row["seconds"] for row in rows if row["mode"] == mode)
        for mode in ("all", "video-only")}, "consumedMetadataIdentical": True,
        "scope": f"Synthetic HEVC MKV, {attachment_mib} MiB attachment, local OS cache, no receiver"}
    (root / "measurement.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    print(f"Report: {root / 'measurement.json'}")


if __name__ == "__main__":
    sys.exit(test_storage.guarded(PROJECT, lambda: campaign() or 0))

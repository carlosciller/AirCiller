"""Local pixel-preserving PNG comparison and Matroska attachment cost, no receiver."""
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
import test_storage


PROJECT = Path(__file__).resolve().parents[1]
ENGINE = PROJECT / ".build/dependencies/AirCillerEngine-ffmpeg-9.0.1-python-3.13.15/ffmpeg/bin"


def run(args):
    result = subprocess.run([str(arg) for arg in args], capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace")[-4000:])
    return result.stdout


def campaign():
    parent = PROJECT / ".build/performance"
    parent.mkdir(exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix="run.", dir=parent))
    test_storage.register_run(PROJECT, root)
    fixture = root / "fixture"
    run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "6", "-strict-concurrency=complete",
         "-warnings-as-errors", "-O", PROJECT / "Tests/BitmapCompressionFixture.swift", "-o", fixture])
    image = root / "source.png"
    run([fixture, image])
    rows = []
    reference = None
    variants = [(6, "paeth"), (6, "none")]
    for iteration in range(3):
        for level, predictor in (variants if iteration % 2 == 0 else list(reversed(variants))):
            frames = root / f"frames-{iteration}-{level}-{predictor}"
            frames.mkdir()
            began = time.monotonic()
            run([ENGINE / "ffmpeg", "-v", "error", "-nostdin", "-loop", "1", "-i", image,
                 "-frames:v", "30", "-c:v", "png", "-compression_level", str(level),
                 "-pred", predictor,
                 "-fps_mode", "passthrough", frames / "%04d.png"])
            seconds = time.monotonic() - began
            outputs = sorted(frames.glob("*.png"))
            pixels = run([ENGINE / "ffmpeg", "-v", "error", "-i", frames / "%04d.png",
                          "-f", "framemd5", "-"])
            if reference is None:
                reference = pixels
            if pixels != reference or len(outputs) != 30:
                raise RuntimeError("Decoded pixel/frame parity failed")
            rows.append({"iteration": iteration, "compression": level, "predictor": predictor, "seconds": seconds,
                         "bytes": sum(path.stat().st_size for path in outputs),
                         "decodedSHA256": hashlib.sha256(pixels).hexdigest()})
            for path in outputs:
                path.unlink()
            frames.rmdir()
    # The same encoded stream with/without a large synthetic font attachment.
    (root / "png-measurement.json").write_text(json.dumps(rows, indent=2) + "\n")
    plain = root / "plain.mkv"
    attached = root / "attached.mkv"
    attachment = root / "synthetic-font.bin"
    attachment.write_bytes(bytes(range(256)) * (24 * 1024 * 1024 // 256))
    # Explicit development encoder, never used by the application or timed probe.
    generator = Path(sys.argv[1]).resolve(strict=True)
    run([generator, "-v", "error", "-f", "lavfi", "-i", "sine=frequency=880",
         "-t", "1", "-c:a", "aac", plain])
    run([ENGINE / "ffmpeg", "-v", "error", "-i", plain, "-map", "0", "-c", "copy",
         "-attach", attachment, "-metadata:s:t", "mimetype=application/x-truetype-font", attached])
    probes = []
    for iteration in range(3):
        for source in ([plain, attached] if iteration % 2 == 0 else [attached, plain]):
            began = time.monotonic()
            run([ENGINE / "ffprobe", "-v", "error", "-show_format", "-show_streams", "-of", "json", source])
            probes.append({"iteration": iteration, "attached": source == attached,
                           "seconds": time.monotonic() - began})
    attachment.unlink()
    result = {"png": rows, "attachmentProbes": probes,
              "scope": "Synthetic local preparation, warm OS cache; not Play-to-picture or real PGS extraction",
              "pngMedianSeconds": {f"{level}-{predictor}": statistics.median(
                  row["seconds"] for row in rows if row["compression"] == level and row["predictor"] == predictor)
                  for level, predictor in variants}}
    (root / "measurement.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    print(f"Report: {root / 'measurement.json'}")


if __name__ == "__main__":
    sys.exit(test_storage.guarded(PROJECT, lambda: campaign() or 0))

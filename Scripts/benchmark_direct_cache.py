"""Actual direct command/probe/cache services, no TV or app install.

Pass a development ffmpeg for the synthetic fixture, or --library /absolute/movie
for one bounded cold/warm comparison with a generated text track. This measures
remux/cache/metadata only, not HDR injection, local AVPlayer or receiver startup.
"""
from pathlib import Path
import sys
import tempfile

sys.dont_write_bytecode = True
from benchmark_bitmap_preparation import ENGINE, PROJECT, run
import test_storage


def campaign():
    root = Path(tempfile.mkdtemp(prefix="run.", dir=PROJECT / ".build/performance"))
    test_storage.register_run(PROJECT, root)
    library = len(sys.argv) == 3 and sys.argv[1] == "--library"
    movie = Path(sys.argv[2]).resolve(strict=True) if library else root / "source.mkv"
    if library and (not movie.is_file() or movie.stat().st_size > 12 * 1024**3):
        raise ValueError("Real input must be a regular file of at most 12 GiB")
    subtitle = root / "caption.eng.srt"
    subtitle.write_text("1\n00:00:00,000 --> 00:00:20,000\nAirCiller cache check\n")
    if not library:
        run([Path(sys.argv[1]).resolve(strict=True), "-v", "error", "-f", "lavfi", "-i",
             "testsrc2=duration=20:size=1280x720:rate=24", "-f", "lavfi", "-i", "sine=frequency=880",
             "-t", "20", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "18", "-c:a", "aac", movie])
    names = ["Localization", "AirCillerError", "ProcessDataBuffer", "CancellableProcess", "BundledEngine",
             "MediaModels", "MediaProbeService", "ExternalVobSub", "HLSAudioTimelineInfo", "PreparedMediaCache",
             "DirectPreparationCache", "VODCommandBuilder"]
    tool = root / "benchmark"
    run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "6", "-strict-concurrency=complete",
         "-module-cache-path", PROJECT / ".build/test-module-cache",
         "-warnings-as-errors", "-O", *[PROJECT / f"Sources/{name}.swift" for name in names],
         PROJECT / "Tests/DirectCachePerformanceBenchmark.swift", "-o", tool])
    print(run([tool, root, movie, subtitle, ENGINE / "ffmpeg", ENGINE / "ffprobe",
               "1" if library else "3"]).decode())
    print(f"Report: {root / 'measurement.json'}")


if __name__ == "__main__":
    sys.exit(test_storage.guarded(PROJECT, lambda: campaign() or 0))

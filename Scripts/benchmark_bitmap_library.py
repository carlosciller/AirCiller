"""Full local bitmap-track preparation with a private cold/warm cache; no TV."""
import plistlib
from pathlib import Path
import sys
import tempfile

sys.dont_write_bytecode = True
from benchmark_bitmap_preparation import PROJECT, ENGINE, run
import test_storage


def campaign():
    source = Path(sys.argv[1]).resolve(strict=True)
    if not source.is_file() or source.stat().st_size > 12 * 1024**3:
        raise ValueError("Expected one real media file of at most 12 GiB")
    root = Path(tempfile.mkdtemp(prefix="run.", dir=PROJECT / ".build/performance"))
    test_storage.register_run(PROJECT, root)
    bundle = root / "measure.app/Contents"
    (bundle / "MacOS").mkdir(parents=True)
    (bundle / "Resources").mkdir()
    (bundle / "Resources/Engine").symlink_to(ENGINE.parent.parent)
    (bundle / "Info.plist").write_bytes(plistlib.dumps({"ACBundledEngineRequired": True}))
    names = ["Localization", "AirCillerError", "ProcessDataBuffer", "CancellableProcess", "BundledEngine",
             "MediaModels", "MediaProbeService", "ExternalVobSub", "PGSSubtitleConverter", "SubtitleOCRService",
             "SubtitleOCRTextNormalizer", "AirCillerStorage"]
    tool = bundle / "MacOS/measure"
    run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "6", "-strict-concurrency=complete",
         "-warnings-as-errors", "-O", "-module-cache-path", PROJECT / ".build/test-module-cache",
         *[PROJECT / f"Sources/{name}.swift" for name in names],
         PROJECT / "Tests/BitmapPreparationBenchmark.swift", "-o", tool])
    print(run([tool, source, root]).decode())
    print(f"Report: {root / 'measurement.json'}")


if __name__ == "__main__":
    sys.exit(test_storage.guarded(PROJECT, lambda: campaign() or 0))

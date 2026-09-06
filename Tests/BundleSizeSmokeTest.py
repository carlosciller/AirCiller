"""Bundle measurement tests use disposable fixtures, never installed applications."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Scripts"))
from check_bundle_size import MAXIMUM_BYTES, measure


class BundleSizeTests(unittest.TestCase):
    def test_report_leaves_no_python_cache(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            bundle = root / "Sample.app"
            (bundle / "Contents").mkdir(parents=True)
            (bundle / "Contents/Info.plist").write_bytes(b"info")
            cache = root / "cache"
            environment = dict(os.environ, PYTHONPYCACHEPREFIX=str(cache))
            environment.pop("PYTHONDONTWRITEBYTECODE", None)
            tool = Path(__file__).resolve().parents[1] / "Scripts/check_bundle_size.py"
            result = subprocess.run([sys.executable, "-B", tool, bundle], env=environment,
                                    capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(cache.exists())

    def test_components_and_symlinks(self):
        with tempfile.TemporaryDirectory() as temporary:
            bundle = Path(temporary) / "Sample.app"
            contents = bundle / "Contents"
            contents.mkdir(parents=True)
            (contents / "Info.plist").write_bytes(b"info")
            engine = contents / "Resources/Engine/ffmpeg"
            engine.mkdir(parents=True)
            (engine / "ffmpeg").write_bytes(b"123456")
            (contents / "alias").symlink_to("Resources/Engine/ffmpeg", target_is_directory=True)
            result = measure(bundle)
            self.assertEqual(result["components"]["ffmpeg"], 6)
            self.assertEqual(result["totalBytes"], 10 + len("Resources/Engine/ffmpeg"))
            external = Path(temporary) / "outside"
            external.mkdir()
            (external / "large").write_bytes(b"a" * 500)
            (contents / "external").symlink_to(external, target_is_directory=True)
            self.assertEqual(measure(bundle)["totalBytes"], result["totalBytes"] + len(str(external)))
            with (contents / "oversize").open("wb") as output:
                output.truncate(MAXIMUM_BYTES + 1)
            command = [sys.executable, str(Path(__file__).resolve().parents[1] / "Scripts/check_bundle_size.py"), str(bundle)]
            self.assertEqual(subprocess.run(command, capture_output=True, timeout=10).returncode, 1)

    def test_missing_bundle_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(ValueError):
                measure(temporary)


if __name__ == "__main__":
    unittest.main()

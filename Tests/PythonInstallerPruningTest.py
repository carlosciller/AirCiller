"""Packaging policy tests operate on disposable unsigned app fixtures only."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Scripts"))
from prune_python_installers import prune


class PythonInstallerPruningTests(unittest.TestCase):
    def fixture(self, root):
        bundle = root / "AirCiller.staged.app"
        runtime = bundle / "Contents/Resources/Engine/airplay/python"
        files = ("bin/python3.13", "bin/pip", "bin/pip3", "bin/pip3.13",
                 "lib/python3.13/ssl.py", "lib/python3.13/LICENSE.txt",
                 "lib/python3.13/ensurepip/_bundled/pip.whl",
                 "lib/python3.13/site-packages/pip/__init__.py",
                 "lib/python3.13/site-packages/pip-26.2.1.dist-info/METADATA",
                 "lib/python3.13/site-packages/pip_other/__init__.py")
        for name in files:
            path = runtime / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(name.encode())
        (runtime / "bin/python3").symlink_to("python3.13")
        return bundle, runtime

    def test_only_unused_installers_are_removed_and_cleanup_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temporary:
            bundle, runtime = self.fixture(Path(temporary))
            removed = prune(bundle)
            self.assertEqual(len(removed), 6)
            for name in ("bin/python3.13", "lib/python3.13/ssl.py", "lib/python3.13/LICENSE.txt",
                         "lib/python3.13/site-packages/pip_other/__init__.py"):
                self.assertEqual((runtime / name).read_bytes(), name.encode())
            self.assertEqual((runtime / "bin/python3").readlink(), Path("python3.13"))
            self.assertFalse((runtime / "lib/python3.13/ensurepip").exists())
            self.assertFalse((runtime / "lib/python3.13/site-packages/pip").exists())
            self.assertEqual(prune(bundle), [])

    def test_ordinary_app_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            bundle, runtime = self.fixture(Path(temporary))
            ordinary = bundle.with_name("AirCiller.app")
            bundle.rename(ordinary)
            with self.assertRaises(ValueError):
                prune(ordinary)
            self.assertTrue((ordinary / runtime.relative_to(bundle) / "bin/pip").exists())

    def test_symlinked_runtime_is_refused_without_touching_its_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            bundle, runtime = self.fixture(root)
            outside = root / "engine-cache"
            runtime.rename(outside)
            runtime.symlink_to(outside, target_is_directory=True)
            with self.assertRaises(ValueError):
                prune(bundle)
            self.assertTrue((outside / "bin/pip").exists())

    def test_bad_target_is_rejected_before_any_removal(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            bundle, runtime = self.fixture(root)
            (runtime / "bin/pip").unlink()
            (runtime / "bin/pip").symlink_to(root / "missing")
            with self.assertRaises(ValueError):
                prune(bundle)
            self.assertTrue((runtime / "lib/python3.13/site-packages/pip/__init__.py").is_file())


if __name__ == "__main__":
    unittest.main()

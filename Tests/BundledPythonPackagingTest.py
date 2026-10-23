"""Check the assembled app against its pinned runtime and dependency sources."""
import hashlib
import os
from pathlib import Path
import stat
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
PROJECT = Path(__file__).resolve().parents[1]
RESOURCES = PROJECT / ".build/AirCiller.app/Contents/Resources"
SOURCE = PROJECT / ".build/dependencies/AirCillerEngine-ffmpeg-9.0.1-python-3.13.15/airplay/python"
RUNTIME = RESOURCES / "Engine/airplay/python"
LIBRARY = Path("lib/python3.13")
INSTALLERS = (LIBRARY / "ensurepip", LIBRARY / "site-packages/pip",
              Path("bin/pip"), Path("bin/pip3"), Path("bin/pip3.13"))


def inventory(root):
    result = {}
    for directory, directories, files in os.walk(root, followlinks=False):
        links = [name for name in directories if (Path(directory) / name).is_symlink()]
        directories[:] = [name for name in directories if name not in links and name != "__pycache__"]
        for name in files + links:
            path = Path(directory) / name
            relative = path.relative_to(root)
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                value = ("link", str(path.readlink()))
            elif stat.S_ISREG(mode):
                value = (stat.S_IMODE(mode), hashlib.sha256(path.read_bytes()).hexdigest())
            else:
                raise ValueError(f"Unsupported runtime entry: {relative}")
            result[relative] = value
    return result


class BundledPythonPackagingTests(unittest.TestCase):
    def test_retained_runtime_is_byte_identical_without_installers(self):
        self.assertTrue(SOURCE.is_dir())
        self.assertTrue(RUNTIME.is_dir())
        excluded = (*INSTALLERS, *(LIBRARY / "site-packages" / path.name for path in
                     (SOURCE / LIBRARY / "site-packages").glob("pip-*.dist-info")))
        expected = {name: value for name, value in inventory(SOURCE).items()
                    if not any(name == prefix or prefix in name.parents for prefix in excluded)}
        self.assertEqual(inventory(RUNTIME), expected)
        for prefix in excluded:
            self.assertFalse((RUNTIME / prefix).exists(), str(prefix))

    def test_dependencies_and_helper_are_unchanged(self):
        expected = inventory(PROJECT / "VendorPython")
        actual = inventory(RESOURCES / "VendorPython")
        marker = Path(".airciller-python-executable")
        expected.pop(marker)
        actual.pop(marker)
        self.assertEqual(actual, expected)
        self.assertEqual((RESOURCES / "AirCillerAirPlay.py").read_bytes(),
                         (PROJECT / "Scripts/airplay_helper.py").read_bytes())

    def test_packaged_python_and_helper_run_offline_without_pip(self):
        python = RUNTIME / "bin/python3"
        code = (
            "import importlib.util, sys; "
            "sys.path.insert(0, sys.argv[1]); "
            "assert importlib.util.find_spec('pip') is None; "
            "assert importlib.util.find_spec('ensurepip') is None; "
            "import ssl, sqlite3, zlib, ctypes, pyatv, aiohttp, requests, zeroconf; "
            "print(sys.version.split()[0])"
        )
        result = subprocess.run([python, "-I", "-B", "-c", code, RESOURCES / "VendorPython"],
                                text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "3.13.15")
        environment = dict(os.environ, PYTHONPATH=str(RESOURCES / "VendorPython"),
                           PYTHONDONTWRITEBYTECODE="1")
        result = subprocess.run([python, "-B", RESOURCES / "AirCillerAirPlay.py", "version"],
                                env=environment, text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('"event": "version"', result.stdout)


if __name__ == "__main__":
    unittest.main()

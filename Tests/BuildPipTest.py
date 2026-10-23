"""Build-installer regressions; network edges use disposable local fixtures."""
import hashlib
from pathlib import Path
import ssl
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.dont_write_bytecode = True
PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "Scripts"))
import build_pip


class BuildPipTests(unittest.TestCase):
    def test_cached_wheel_is_verified_without_network(self):
        with tempfile.TemporaryDirectory() as temporary:
            wheel = Path(temporary) / build_pip.WHEEL
            wheel.write_bytes(b"verified fixture")
            with patch.object(build_pip, "SHA256", hashlib.sha256(wheel.read_bytes()).hexdigest()), \
                    patch.object(build_pip.subprocess, "run") as network:
                self.assertEqual(build_pip.verified_wheel(Path(temporary)), wheel)
            network.assert_not_called()

    def test_corrupt_or_symlinked_cache_is_never_executed_or_redownloaded(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            wheel = root / build_pip.WHEEL
            wheel.write_bytes(b"corrupt")
            with patch.object(build_pip.subprocess, "run") as network:
                with self.assertRaises(ValueError):
                    build_pip.verified_wheel(root)
                wheel.unlink()
                wheel.symlink_to(root / "missing")
                with self.assertRaises(ValueError):
                    build_pip.verified_wheel(root)
            network.assert_not_called()

    def test_bad_download_is_rejected_and_temporary_file_removed(self):
        def download(arguments, **kwargs):
            Path(arguments[-1]).write_bytes(b"untrusted response")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with patch.object(build_pip.subprocess, "run", side_effect=download) as network:
                with self.assertRaises(ValueError):
                    build_pip.verified_wheel(root)
            self.assertEqual(list(root.iterdir()), [])
            self.assertIn("--max-filesize", network.call_args.args[0])
            self.assertIn("=https", network.call_args.args[0])

    def test_interrupted_download_is_not_promoted(self):
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(build_pip.subprocess, "run", side_effect=subprocess.TimeoutExpired("curl", 65)):
                with self.assertRaises(subprocess.TimeoutExpired):
                    build_pip.verified_wheel(Path(temporary))
            self.assertEqual(list(Path(temporary).iterdir()), [])

    def test_oversized_wheel_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            wheel = Path(temporary) / "large.whl"
            with wheel.open("wb") as stream:
                stream.truncate(build_pip.MAXIMUM_BYTES + 1)
            with self.assertRaises(ValueError):
                build_pip.verify(wheel)

    def test_real_verified_installer_excludes_compromised_root(self):
        wheel = build_pip.CACHE / build_pip.WHEEL
        build_pip.verify(wheel)  # Prepared by requirements_lock.sh; no download in this test.
        with zipfile.ZipFile(wheel) as archive:
            pem = archive.read("pip/_vendor/certifi/cacert.pem").decode("ascii")
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.load_verify_locations(cadata=pem)
        roots = context.get_ca_certs(binary_form=True)
        self.assertGreater(len(roots), 100)
        self.assertNotIn("86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b",
                         {hashlib.sha256(root).hexdigest() for root in roots})
        result = subprocess.run([sys.executable, "-I", "-B", PROJECT / "Scripts/build_pip.py", "--version"],
                                capture_output=True, text=True, timeout=15, check=True)
        self.assertIn(f"pip {build_pip.VERSION} from {wheel}/pip", result.stdout)
        self.assertIn(f'pip_version="{build_pip.VERSION}"',
                      (PROJECT / "Scripts/requirements_lock.sh").read_text())


if __name__ == "__main__":
    unittest.main()

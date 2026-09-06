import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class SigningIdentityTests(unittest.TestCase):
    def test_selection_is_data_and_never_silent_fallback(self):
        resolver = Path(__file__).resolve().parents[1] / "Scripts/signing_identity.sh"
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / ".local-signing-identity"
            environment = {k: v for k, v in os.environ.items() if k != "AIRCILLER_SIGNING_IDENTITY"}

            def resolve(override=None):
                env = dict(environment)
                if override is not None:
                    env["AIRCILLER_SIGNING_IDENTITY"] = override
                return subprocess.run(["/bin/zsh", str(resolver), directory], env=env, capture_output=True, text=True, timeout=5)

            self.assertEqual(resolve().stdout.strip(), "-")
            fingerprint = "12AB" * 10
            config.write_text(fingerprint + "\n")
            self.assertEqual(resolve().stdout.strip(), fingerprint)
            self.assertEqual(resolve("-").stdout.strip(), "-")
            for invalid in ("", "not-a-certificate", "12AB", "$(touch SHOULD_NOT_EXIST)", fingerprint + "\nextra"):
                self.assertNotEqual(resolve(invalid).returncode, 0)
                config.write_text(invalid)
                self.assertNotEqual(resolve().returncode, 0)
            config.unlink()
            config.symlink_to(Path(directory) / "missing")
            self.assertNotEqual(resolve().returncode, 0)


if __name__ == "__main__":
    unittest.main()

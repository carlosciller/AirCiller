"""Distribution diagnostics with simulated signing tools, without Keychain access."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

script = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "Scripts/audit_distribution.sh"
with tempfile.TemporaryDirectory(prefix="airciller-audit-") as temporary:
    root = Path(temporary)
    app = root / "runtime-name.app"
    resources = app / "Contents/Resources"
    marker = resources / "VendorPython/.airciller-python-executable"
    marker.parent.mkdir(parents=True)
    marker.write_text("Engine/python\n")
    for name in ("Engine/python", "Engine/ffmpeg/bin/ffmpeg", "Engine/ffmpeg/bin/ffprobe"):
        file = resources / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text("#!/bin/sh\nexit 0\n")
        file.chmod(0o755)
    commands = root / "commands"
    commands.mkdir()
    mock = """#!/bin/sh
if [ "$1" = '-d' ]; then
  printf '%s\\n' "$AUDIT_DETAILS"
  exit "$AUDIT_DESCRIBE"
fi
for arg in "$@"; do
  case "$arg" in
    -R=*) test "$arg" = '-R=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' || exit 9
          exit "$AUDIT_DEVELOPER_ID" ;;
  esac
done
exit "$AUDIT_STRUCTURE"
"""
    for name, source in (("codesign", mock), ("xcrun", "#!/bin/sh\nexit 0\n"), ("spctl", "#!/bin/sh\nexit 0\n")):
        file = commands / name
        file.write_text(source)
        file.chmod(0o755)
    cases = [
        ("adhoc", "Signature=adhoc", 1, 0, 0, False, False),
        ("local", "Authority=Local Development\nExecutable=/tmp/runtime.app", 1, 0, 0, False, False),
        ("developer", "CodeDirectory v=20500 size=100 flags=0x10000(runtime) hashes=1", 0, 0, 0, True, True),
        ("mixed flags", "CodeDirectory v=20500 size=100 flags=0x10002(adhoc,runtime) hashes=1", 1, 0, 0, False, True),
        ("invalid", "Authority=Developer ID Application: Example", 1, 1, 0, False, False),
        ("description failed", "runtime", 1, 1, 1, False, False),
    ]
    for name, details, developer, structure, describe, expected_id, expected_runtime in cases:
        environment = dict(os.environ, PATH=str(commands) + ":/usr/bin:/bin",
                           AUDIT_DETAILS=details, AUDIT_DEVELOPER_ID=str(developer),
                           AUDIT_STRUCTURE=str(structure), AUDIT_DESCRIBE=str(describe))
        result = subprocess.run(["/bin/zsh", str(script), str(app)], env=environment, capture_output=True, text=True)
        assert ("Developer ID signature: present" in result.stdout) == expected_id, (name, result.stdout)
        assert ("Hardened Runtime: enabled" in result.stdout) == expected_runtime, (name, result.stdout)
        assert (result.returncode == 0) == (expected_id and expected_runtime and structure == 0), (name, result.stdout)
print("Distribution audit regression checks: OK (6 cases)")

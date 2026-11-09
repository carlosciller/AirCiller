"""Stage signed interactive test builds at one stable, user-owned location."""
import argparse
import fcntl
import plistlib
import re
import shutil
import subprocess
from pathlib import Path

IDENTIFIER = "local.carlosciller.AirCiller.PlaybackChecks"


def installation_root():
    return Path.home() / "Movies" / "AirCiller Tests"


def installed_binary():
    return installation_root() / "AirCiller Test.app/Contents/MacOS/AirCiller"


def verified_identity(app):
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleIdentifier") != IDENTIFIER or info.get("CFBundleExecutable") != "AirCiller":
        raise ValueError("Not an AirCiller test application")
    try:
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict",
                        "-R=anchor apple generic", str(app)], check=True, capture_output=True, timeout=30)
        details = subprocess.run(["/usr/bin/codesign", "-d", "-r-", "--verbose=4", str(app)],
                                 check=True, capture_output=True, text=True, timeout=15)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise ValueError("Test app requires a valid Apple-issued signature; no app was launched") from error
    output = details.stdout + details.stderr
    digest = re.search(r"^CDHash=([0-9a-f]+)$", output, re.M)
    requirement = re.search(r"^designated => (.+)$", output, re.M)
    if not digest or not requirement:
        raise ValueError("Missing stable signing identity")
    return digest.group(1), requirement.group(1)


def stage(source, root=None):
    root = Path(root or installation_root())
    if root.is_symlink():
        raise ValueError("Test installation directory cannot be a symlink")
    root.mkdir(parents=True, exist_ok=True)
    lock = root / ".staging.lock"
    if lock.is_symlink():
        raise ValueError("Test installation lock cannot be a symlink")
    with lock.open("a") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return _stage(source, root)


def _stage(source, root):
    source = Path(source).resolve(strict=True)
    root = Path(root)
    if root.is_symlink():
        raise ValueError("Test installation directory cannot be a symlink")
    root.mkdir(parents=True, exist_ok=True)
    target = root / "AirCiller Test.app"
    staged = root / "AirCiller Test.staged.app"
    previous = root / "AirCiller Test.previous.app"
    identity = verified_identity(source)
    for path in (target, staged, previous):
        if path.is_symlink():
            raise ValueError("Test application paths cannot be symlinks")
    if target.exists():
        old_identity = verified_identity(target)
        if old_identity == identity:
            return target / "Contents/MacOS/AirCiller"
        if old_identity[1] != identity[1]:
            raise ValueError("Test signing identity changed; explicit migration required")
    # Never replace a running test app. Process-list failure is a hard failure.
    processes = subprocess.run(["/bin/ps", "-axo", "comm="], check=True,
                               capture_output=True, text=True, timeout=10).stdout.splitlines()
    if str(target / "Contents/MacOS/AirCiller") in (p.strip() for p in processes):
        raise ValueError("Quit the running test application before staging another build")
    if staged.exists() or previous.exists():
        raise ValueError("An interrupted test installation needs review before staging")
    shutil.copytree(source, staged, symlinks=True)
    if verified_identity(staged) != identity:
        raise ValueError("Copied test application failed identity verification")
    if target.exists():
        target.rename(previous)
    try:
        staged.rename(target)
    except OSError:
        if previous.exists():
            previous.rename(target)
        raise
    if previous.exists():
        # Only the previously verified test bundle owned by this staging operation.
        shutil.rmtree(previous)
    return target / "Contents/MacOS/AirCiller"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    print(stage(args.app))

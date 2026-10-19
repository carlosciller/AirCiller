"""Bound generated test storage, never user media or installed applications.

Only completed, owned run directories in three explicit test roots are eligible.
Reports, screenshots, source snapshots and manifests remain at their original paths.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

LIMIT_BYTES = 12 * 1024**3
ROOTS = {
    "startup-benchmark": ("run.", "measurement-", "live-"),
    "performance": ("run.",),
    "playback-checks": ("run-", "capture-run-"),
}
MARKER = ".airciller-test-storage.json"
DISPOSABLE = frozenset({
    ".mkv", ".mp4", ".mov", ".m4v", ".m4s", ".ts", ".mts", ".m2ts",
    ".aac", ".ac3", ".eac3", ".flac", ".wav", ".pcm", ".aiff", ".caf",
    ".hevc", ".h264", ".h265", ".yuv", ".zip", ".delta", ".o", ".a",
    ".dylib", ".swiftmodule", ".swiftdoc", ".swiftsourceinfo", ".pyc", ".dia",
})
MACHO = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf",
         b"\xfe\xed\xfa\xce", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}


def files(directory):
    for parent, dirs, names in os.walk(directory, followlinks=False):
        dirs[:] = [name for name in dirs if not (Path(parent) / name).is_symlink()]
        for name in names:
            path = Path(parent) / name
            if not path.is_symlink() and path.is_file():
                yield path


def allocated_size(directory):
    # Account for hard links once; never traverse symbolic links.
    seen = set()
    total = 0
    for path in files(directory):
        stat = path.stat()
        identity = (stat.st_dev, stat.st_ino)
        if identity not in seen:
            total += stat.st_blocks * 512
            seen.add(identity)
    return total


def build_directory(project):
    build = project / ".build"
    if build.is_symlink():
        raise ValueError("Refusing a symbolic-link .build directory")
    build.mkdir(exist_ok=True)
    return build


def runs(build):
    for name, prefixes in ROOTS.items():
        parent = build / name
        if not parent.is_dir() or parent.is_symlink():
            continue
        for path in parent.iterdir():
            if path.is_dir() and not path.is_symlink() and path.name.startswith(prefixes):
                yield path


def write_marker(run, data):
    destination = run / MARKER
    temporary = run / (MARKER + ".tmp")
    if destination.is_symlink() or temporary.is_symlink():
        raise ValueError("Refusing symbolic-link retention metadata")
    temporary.write_text(json.dumps(data, indent=2) + "\n")
    temporary.replace(destination)


def register_run(project, run):
    token = os.environ.get("AIRCILLER_TEST_STORAGE_OWNER")
    if not token:
        return  # Imported unit-test helpers do not own a retention session.
    build = build_directory(project)
    if run not in set(runs(build)):
        raise ValueError("Run is not inside an approved generated-test root")
    if (run / MARKER).exists() or (run / MARKER).is_symlink():
        raise ValueError("Run already has retention metadata")
    write_marker(run, {"schema": 1, "status": "active", "owner": token})


def prune(run):
    marker = run / MARKER
    if not marker.is_file() or marker.is_symlink():
        return
    state = json.loads(marker.read_text())
    if state.get("schema") != 1 or state.get("status") != "complete":
        return
    removed = state.setdefault("removedGeneratedFiles", [])
    for path in files(run):
        disposable = path.suffix.lower() in DISPOSABLE
        if not disposable and os.access(path, os.X_OK):
            with path.open("rb") as stream:
                disposable = stream.read(4) in MACHO
        if disposable:
            # Persist intent before deletion; interrupted cleanup remains auditable.
            removed.append(str(path.relative_to(run)))
            write_marker(run, state)
            path.unlink()
    state["prunedAtUnix"] = time.time()
    write_marker(run, state)


def preflight(build, limit=LIMIT_BYTES):
    for run in runs(build):
        prune(run)
    size = allocated_size(build)
    if size >= limit:
        raise ValueError(
            f"Test storage is {size / 1024**3:.1f} GiB (admission limit {limit / 1024**3:.1f} GiB). "
            "No new test was started. Reports, tools and rollback copies were not deleted. "
            "Review .build before continuing; do not increase the limit to hide accumulation."
        )
    return size


def guarded(project, action, limit=LIMIT_BYTES):
    build = build_directory(project)
    lock_path = build / ".test-storage.lock"
    if lock_path.is_symlink():
        raise ValueError("Refusing symbolic-link storage lock")
    with lock_path.open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError("Another guarded test is running; no cleanup was attempted") from error
        preflight(build, limit)
        token = uuid.uuid4().hex
        previous_owner = os.environ.get("AIRCILLER_TEST_STORAGE_OWNER")
        os.environ["AIRCILLER_TEST_STORAGE_OWNER"] = token
        outcome = "interrupted"
        try:
            result = action()
            outcome = result
            return result
        finally:
            for run in runs(build):
                marker = run / MARKER
                if not marker.is_file() or marker.is_symlink():
                    continue
                state = json.loads(marker.read_text())
                if state.get("owner") == token:
                    state.update(status="complete", exitCode=outcome)
                    write_marker(run, state)
                    prune(run)
            if previous_owner is None:
                os.environ.pop("AIRCILLER_TEST_STORAGE_OWNER", None)
            else:
                os.environ["AIRCILLER_TEST_STORAGE_OWNER"] = previous_owner
            size = allocated_size(build)
            print(f"Test storage: {size / 1024**3:.2f} GiB; reports retained.", file=sys.stderr)
            if size >= limit:
                print("Admission limit reached; subsequent tests will be blocked.", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("clean", "run", "register"))
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    project = Path(__file__).resolve().parent.parent
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if args.mode == "run" and not command:
        parser.error("run requires a command after --")
    if args.mode == "register":
        if len(command) != 1:
            parser.error("register requires exactly one generated run directory")
        register_run(project, Path(command[0]))
        return 0
    def action():
        if args.mode == "clean":
            return 0
        environment = dict(os.environ, AIRCILLER_TEST_STORAGE_CHILD=command[0])
        return subprocess.call(command, env=environment)
    try:
        return guarded(project, action)
    except (OSError, ValueError) as error:
        print(f"Test storage: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

"""Run the hash-verified build-time pip, without changing the selected interpreter.

The wheel and SHA-256 are from the Python security announcement:
https://discuss.python.org/t/109576
No installed pip or ensurepip is used to download or execute this bootstrap.
"""
import hashlib
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile

VERSION = "26.2.2"
SHA256 = "fd7f4dfa8190e014013b9f08f3e973f4e4c26ffd179a204895533a7254813a70"
WHEEL = f"pip-{VERSION}-py3-none-any.whl"
URL = ("https://files.pythonhosted.org/packages/3f/06/"
       "3e4420302363fbb71be3c7f35ce042f54bfca330e3e66b3a2e3c4cca579f/" + WHEEL)
MAXIMUM_BYTES = 3_000_000
CACHE = Path(__file__).resolve().parents[1] / ".build/dependencies/build-pip"


def verify(path):
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= MAXIMUM_BYTES:
        raise ValueError("Invalid build-pip wheel")
    if hashlib.sha256(path.read_bytes()).hexdigest() != SHA256:
        raise ValueError("Build-pip wheel SHA-256 mismatch; do not execute this cache entry")


def verified_wheel(cache=CACHE):
    cache.mkdir(parents=True, exist_ok=True)
    wheel = cache / WHEEL
    if wheel.exists() or wheel.is_symlink():
        verify(wheel)
        return wheel
    descriptor, name = tempfile.mkstemp(prefix=".pip-download-", dir=cache)
    os.close(descriptor)
    temporary = Path(name)
    try:
        # System curl uses its own TLS validation, not the old pip CA bundle.
        # The immutable direct URL needs no redirect or unverified installer.
        subprocess.run([
            "/usr/bin/curl", "--fail", "--silent", "--show-error", "--proto", "=https",
            "--connect-timeout", "15", "--max-time", "60", "--max-filesize", str(MAXIMUM_BYTES),
            URL, "--output", str(temporary),
        ], check=True, timeout=65)
        verify(temporary)
        temporary.replace(wheel)
    finally:
        temporary.unlink(missing_ok=True)
    return wheel


def main(arguments):
    if arguments == ["--version-pin"]:
        print(VERSION)
        return
    wheel = verified_wheel()
    if arguments == ["--install-self"]:
        arguments = ["install", "--no-index", "--no-deps", "--no-compile", str(wheel)]
    sys.path.insert(0, str(wheel))
    import pip
    if pip.__version__ != VERSION or not pip.__file__.startswith(str(wheel) + "/"):
        raise RuntimeError("Build pip did not load from the verified wheel")
    os.environ["PIP_CONFIG_FILE"] = os.devnull
    sys.argv = ["pip", "--isolated", "--disable-pip-version-check", *arguments]
    runpy.run_module("pip", run_name="__main__")


if __name__ == "__main__":
    main(sys.argv[1:])

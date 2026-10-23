"""Exclude unused package installers from an unsigned, staged AirCiller app only."""
import argparse
from pathlib import Path
import re
import shutil


def installer_paths(bundle):
    # Never accept an installed app, a cached engine or a symlinked staging root.
    if bundle.is_symlink() or not bundle.name.endswith(".staged.app"):
        raise ValueError("Expected an unsigned .staged.app, not an installed application")
    relative = Path("Contents/Resources/Engine/airplay/python")
    runtime = bundle / relative
    for parent in (bundle, *[bundle / Path(*relative.parts[:i]) for i in range(1, len(relative.parts) + 1)]):
        if parent.is_symlink() or not parent.is_dir():
            raise ValueError("Runtime staging directories must not be symlinks")
    for suffix in ("bin", "lib", "lib/python3.13", "lib/python3.13/site-packages"):
        path = runtime / suffix
        if path.is_symlink() or not path.is_dir():
            raise ValueError("Invalid runtime directory")
    library = runtime / "lib/python3.13"
    packages = library / "site-packages"
    paths = [packages / "pip", library / "ensurepip"]
    paths += sorted(path for path in packages.iterdir()
                    if re.fullmatch(r"pip-[0-9][A-Za-z0-9.+-]*\.dist-info", path.name))
    paths += [runtime / "bin" / name for name in ("pip", "pip3", "pip3.13")]
    # Validate every target before deleting any of them. rmtree does not follow
    # internal symlinks; reject target aliases rather than deleting their targets.
    for path in paths:
        if path.is_symlink():
            raise ValueError("Installer target must not be a symlink")
        if path.exists() and not (path.is_file() or path.is_dir()):
            raise ValueError("Unsupported installer entry")
    return [path for path in paths if path.exists()]


def prune(bundle):
    paths = installer_paths(bundle)
    removed = []
    for path in paths:
        if path.is_dir():
            shutil.rmtree(path)
        elif path.is_file():
            path.unlink()
        else:
            raise ValueError("Unsupported installer entry")
        removed.append(path.relative_to(bundle).as_posix())
    return removed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    args = parser.parse_args()
    for removed in prune(args.bundle):
        print(f"Excluded build-only installer: {removed}")

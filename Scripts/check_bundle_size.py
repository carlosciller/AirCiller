"""Read-only logical bundle size report and release budget. No symlink traversal."""
import argparse
import json
import os
from pathlib import Path
import stat

MAXIMUM_BYTES = 165_000_000
COMPONENTS = {
    "ffmpeg": "Contents/Resources/Engine/ffmpeg/",
    "python": "Contents/Resources/Engine/airplay/",
    "airplay_dependencies": "Contents/Resources/VendorPython/",
    "application": "Contents/MacOS/",
    "updater": "Contents/Frameworks/",
}


def measure(bundle):
    bundle = Path(bundle)
    if bundle.is_symlink() or not (bundle / "Contents/Info.plist").is_file():
        raise ValueError("Expected an application bundle")
    totals = dict.fromkeys((*COMPONENTS, "other"), 0)
    for root, directories, files in os.walk(bundle, followlinks=False):
        # Count symlink storage once, never its target (including framework aliases).
        links = [name for name in directories if (Path(root) / name).is_symlink()]
        directories[:] = [name for name in directories if name not in links]
        for name in files + links:
            path = Path(root) / name
            info = path.lstat()
            if not (stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode)):
                raise ValueError("Unsupported bundle entry")
            relative = path.relative_to(bundle).as_posix()
            component = next((key for key, prefix in COMPONENTS.items() if relative.startswith(prefix)), "other")
            totals[component] += info.st_size
    return {"measurement": "logical_bytes_without_following_symlinks", "components": totals,
            "totalBytes": sum(totals.values()), "maximumBytes": MAXIMUM_BYTES}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    args = parser.parse_args()
    try:
        result = measure(args.bundle)
    except (OSError, ValueError) as error:
        parser.exit(2, f"Bundle size check failed: {error}\n")
    result["withinBudget"] = result["totalBytes"] <= MAXIMUM_BYTES
    print(json.dumps(result, indent=2))
    return 0 if result["withinBudget"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

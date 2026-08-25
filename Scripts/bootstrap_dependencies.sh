#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
build_dir="$project_dir/.build"
target="$project_dir/VendorPython"
staged="$build_dir/VendorPython.staged"
previous="$build_dir/VendorPython.previous"

if [[ -n "${AIRCILLER_PYTHON:-}" ]]; then
  python_path="$AIRCILLER_PYTHON"
elif [[ -x /opt/homebrew/opt/python@3.13/bin/python3.13 ]]; then
  python_path="/opt/homebrew/opt/python@3.13/bin/python3.13"
elif [[ -x /opt/homebrew/bin/python3.13 ]]; then
  python_path="/opt/homebrew/bin/python3.13"
elif [[ -x /opt/homebrew/bin/python3 ]]; then
  python_path="/opt/homebrew/bin/python3"
elif [[ -x /usr/local/opt/python@3.13/bin/python3.13 ]]; then
  python_path="/usr/local/opt/python@3.13/bin/python3.13"
elif [[ -x /usr/local/bin/python3.13 ]]; then
  python_path="/usr/local/bin/python3.13"
elif [[ -x /usr/local/bin/python3 ]]; then
  python_path="/usr/local/bin/python3"
else
  echo "AirCiller requires Python 3.13. Install python@3.13 with Homebrew or set AIRCILLER_PYTHON." >&2
  exit 2
fi

if [[ ! -x "$python_path" ]]; then
  echo "The selected interpreter does not exist or is not executable: $python_path" >&2
  exit 2
fi

if ! "$python_path" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 13) else 1)'; then
  echo "AirCiller requires Python 3.13: $($python_path --version 2>&1)" >&2
  exit 2
fi

mkdir -p "$build_dir"
rm -rf "$staged" "$previous"
mkdir -p "$staged"

"$python_path" -m pip install \
  --disable-pip-version-check \
  --require-hashes \
  --no-compile \
  --no-warn-script-location \
  --requirement "$project_dir/requirements.lock" \
  --target "$staged"

rm -rf "$staged/bin"
find "$staged" -type d -name __pycache__ -prune -exec rm -rf {} +
printf '%s\n' "$python_path" > "$staged/.airciller-python-executable"

PYTHONPATH="$staged" "$python_path" -c 'import pyatv, aiohttp, requests, zeroconf'

if [[ -e "$target" ]]; then
  mv "$target" "$previous"
fi
if mv "$staged" "$target"; then
  rm -rf "$previous"
else
  [[ ! -e "$target" && -e "$previous" ]] && mv "$previous" "$target"
  exit 1
fi

echo "AirPlay engine prepared with $($python_path --version 2>&1): $target"

#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
build_dir="$project_dir/.build"
python_version="3.13.15"
pip_version="26.2.1"
pip_tools_version="7.6.1"
tools_root="$build_dir/dependencies/requirements-tools-python-$python_version-pip-$pip_version-pip-tools-$pip_tools_version"
mode="${1:-check}"

case "$mode" in
  check | update | upgrade) ;;
  *)
    echo "Usage: $0 [check|update|upgrade]" >&2
    exit 2
    ;;
esac

if [[ -n "${AIRCILLER_PYTHON:-}" ]]; then
  python_path="$AIRCILLER_PYTHON"
elif [[ -x /opt/homebrew/opt/python@3.13/bin/python3.13 ]]; then
  python_path="/opt/homebrew/opt/python@3.13/bin/python3.13"
elif [[ -x /opt/homebrew/bin/python3.13 ]]; then
  python_path="/opt/homebrew/bin/python3.13"
elif [[ -x /usr/local/opt/python@3.13/bin/python3.13 ]]; then
  python_path="/usr/local/opt/python@3.13/bin/python3.13"
elif command -v python3.13 >/dev/null 2>&1; then
  python_path="$(command -v python3.13)"
elif command -v python3 >/dev/null 2>&1; then
  python_path="$(command -v python3)"
else
  echo "Python 3.13 is required to compile requirements.lock." >&2
  exit 2
fi

if [[ "$($python_path -c 'import platform; print(platform.python_version())')" != "$python_version" ]]; then
  echo "requirements.lock must be compiled with Python $python_version: $($python_path --version 2>&1)" >&2
  exit 2
fi

mkdir -p "$build_dir/dependencies"
if [[ ! -x "$tools_root/bin/python" ]]; then
  staged_tools="$(mktemp -d "$build_dir/dependencies/requirements-tools.staged.XXXXXX")"
  "$python_path" -m venv "$staged_tools"
  "$staged_tools/bin/python" -m pip install \
    --disable-pip-version-check \
    "pip==$pip_version" \
    "pip-tools==$pip_tools_version" \
    "build==1.6.0" \
    "click==8.5.0" \
    "packaging==26.3" \
    "pyproject-hooks==1.2.0" \
    "setuptools==84.0.0" \
    "wheel==0.48.0"
  mv "$staged_tools" "$tools_root"
fi

if [[ "$($tools_root/bin/python -m pip --version)" != "pip $pip_version "* ]]; then
  echo "The requirements compiler has an unexpected pip version." >&2
  exit 3
fi
if [[ "$($tools_root/bin/python -m piptools compile --version)" != "python -m piptools, version $pip_tools_version" ]]; then
  echo "The requirements compiler has an unexpected pip-tools version." >&2
  exit 3
fi

staged_lock="$(mktemp "$build_dir/requirements.lock.XXXXXX")"
trap 'rm -f "$staged_lock"' EXIT
cp "$project_dir/requirements.lock" "$staged_lock"

compile_arguments=(
  --generate-hashes
  --output-file="$staged_lock"
  --quiet
  --strip-extras
)
if [[ "$mode" == "upgrade" ]]; then
  compile_arguments+=(--upgrade)
fi

(
  cd "$project_dir"
  CUSTOM_COMPILE_COMMAND="./Scripts/requirements_lock.sh update" \
    "$tools_root/bin/python" -m piptools compile \
    "${compile_arguments[@]}" \
    requirements.in
)

if [[ "$mode" == "check" ]]; then
  if ! cmp -s "$project_dir/requirements.lock" "$staged_lock"; then
    echo "requirements.lock does not match requirements.in and the pinned compiler." >&2
    diff -u "$project_dir/requirements.lock" "$staged_lock" || true
    exit 4
  fi
  echo "requirements.lock is reproducible with Python $python_version, pip $pip_version, and pip-tools $pip_tools_version."
else
  mv "$staged_lock" "$project_dir/requirements.lock"
  trap - EXIT
  echo "requirements.lock updated with Python $python_version, pip $pip_version, and pip-tools $pip_tools_version."
fi

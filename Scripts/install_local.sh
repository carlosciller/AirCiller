#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
source_app="$project_dir/.build/AirCiller.app"

if (( $# != 1 )); then
  echo "Usage: ./Scripts/install_local.sh /explicit/path/AirCiller.app" >&2
  exit 2
fi

target_app="${1:A}"
target_parent="${target_app:h}"
staged_app="$target_parent/.AirCiller.installing.app"
rollback_app="$target_parent/AirCiller.rollback.app"

if [[ ! -d "$source_app" ]]; then
  echo "Build AirCiller with ./build.sh first." >&2
  exit 2
fi

if pgrep -x AirCiller >/dev/null 2>&1; then
  echo "Quit AirCiller before installing a candidate." >&2
  exit 2
fi

rm -rf "$staged_app"
ditto "$source_app" "$staged_app"
codesign --verify --deep --strict "$staged_app"

if [[ -e "$target_app" ]]; then
  rm -rf "$rollback_app"
  mv "$target_app" "$rollback_app"
fi

if mv "$staged_app" "$target_app"; then
  echo "Installed: $target_app"
  [[ -e "$rollback_app" ]] && echo "Rollback copy: $rollback_app"
else
  [[ ! -e "$target_app" && -e "$rollback_app" ]] && mv "$rollback_app" "$target_app"
  exit 1
fi

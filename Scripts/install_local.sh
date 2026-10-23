#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
source_app="$project_dir/.build/AirCiller.app"

if (( $# != 1 )); then
  echo "Usage: ./Scripts/install_local.sh /explicit/path/AirCiller.app" >&2
  exit 2
fi

target_input="${1:a}"
if [[ "${target_input:t}" != "AirCiller.app" || -L "$target_input" ]]; then
  echo "The installation target must be an explicit, non-symlink AirCiller.app bundle." >&2
  exit 2
fi
target_app="${target_input:A}"
target_parent="${target_app:h}"
staged_app="$target_parent/.AirCiller.installing.app"
rollback_app="$target_parent/AirCiller.rollback.app"

is_airciller_bundle() {
  local bundle="$1"
  [[ -d "$bundle" && ! -L "$bundle" && -f "$bundle/Contents/Info.plist" ]] \
    && [[ "$(plutil -extract CFBundleIdentifier raw "$bundle/Contents/Info.plist" 2>/dev/null)" \
      == "local.carlosciller.AirCiller" ]]
}

if ! is_airciller_bundle "$source_app"; then
  echo "Build the ordinary AirCiller app with ./build.sh first." >&2
  exit 2
fi
if [[ ! -d "$target_parent" || "$target_app" == "${source_app:A}" ]]; then
  echo "Choose an existing destination folder outside the source bundle." >&2
  exit 2
fi

# Check every path that may be moved or removed before touching any of them.
for existing in "$target_app" "$staged_app" "$rollback_app"; do
  if [[ -e "$existing" || -L "$existing" ]] && ! is_airciller_bundle "$existing"; then
    echo "Refusing to replace a symlink or an item that is not an AirCiller bundle: $existing" >&2
    exit 2
  fi
done

if pgrep -x AirCiller >/dev/null 2>&1; then
  echo "Quit AirCiller before installing a candidate." >&2
  exit 2
fi

codesign --verify --deep --strict "$source_app"
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

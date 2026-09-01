#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
dependencies_dir="$project_dir/.build/dependencies"
engine_name="AirCillerEngine-ffmpeg-9.0.1-python-3.13.15"
engine_path="$dependencies_dir/$engine_name"
downloads_dir="$dependencies_dir/downloads"
staging_path="$dependencies_dir/.$engine_name.staging"
previous_path="$dependencies_dir/.$engine_name.previous"

release_base="https://github.com/carlosciller/AirCiller/releases/download/v0.10.3"
ffmpeg_archive="ffmpeg-9.0.1-macos-arm64.zip"
ffmpeg_sha256="059a683433d3b05f7fe1f2231942cebeb51bbbded3cbed46da1d702f3a451c83"
airplay_archive="airplay-python-3.13.15-macos-arm64.zip"
airplay_sha256="4481b749d5a147f1762026940387ed4476d71d98edf781532a8d0949ea883221"

verify_archive() {
  local archive_path="$1"
  local expected="$2"
  local actual
  actual="$(shasum -a 256 "$archive_path" | cut -d ' ' -f 1)"
  [[ "$actual" == "$expected" ]]
}

download_archive() {
  local name="$1"
  local expected="$2"
  local archive_path="$downloads_dir/$name"

  if [[ -f "$archive_path" ]] && ! verify_archive "$archive_path" "$expected"; then
    rm -f "$archive_path"
  fi
  if [[ ! -f "$archive_path" ]]; then
    curl --fail --location --progress-bar "$release_base/$name" --output "$archive_path"
  fi
  if ! verify_archive "$archive_path" "$expected"; then
    echo "SHA-256 verification failed for $name" >&2
    exit 3
  fi
}

validate_engine() {
  local root="$1"
  [[ -x "$root/ffmpeg/bin/ffmpeg" ]]
  [[ -x "$root/ffmpeg/bin/ffprobe" ]]
  [[ -f "$root/ffmpeg/LICENSES/FFmpeg-LGPL-2.1.txt" ]]
  [[ -x "$root/airplay/python/bin/python3" ]]
  "$root/ffmpeg/bin/ffmpeg" -version 2>&1 | grep -q '^ffmpeg version 9\.0\.1'
  "$root/airplay/python/bin/python3" --version 2>&1 | grep -q '^Python 3\.13\.15$'
}

if validate_engine "$engine_path" 2>/dev/null; then
  echo "$engine_path"
  exit 0
fi

mkdir -p "$dependencies_dir" "$downloads_dir"
download_archive "$ffmpeg_archive" "$ffmpeg_sha256"
download_archive "$airplay_archive" "$airplay_sha256"

rm -rf "$staging_path" "$previous_path"
mkdir -p "$staging_path"
ditto -x -k --norsrc --noextattr --noqtn --noacl \
  "$downloads_dir/$ffmpeg_archive" "$staging_path"
ditto -x -k --norsrc --noextattr --noqtn --noacl \
  "$downloads_dir/$airplay_archive" "$staging_path"

if ! validate_engine "$staging_path"; then
  echo "The bundled playback engine did not pass validation." >&2
  exit 3
fi

if [[ -e "$engine_path" ]]; then
  mv "$engine_path" "$previous_path"
fi
if mv "$staging_path" "$engine_path"; then
  rm -rf "$previous_path"
else
  [[ ! -e "$engine_path" && -e "$previous_path" ]] && mv "$previous_path" "$engine_path"
  exit 1
fi

echo "$engine_path"

#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
build_root="$project_dir/.build/managed-components"
downloads="$build_root/downloads"
staging="$build_root/staging"
output="$build_root/output"

ffmpeg_version="9.0.1"
ffmpeg_sha256="cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635"
ffmpeg_url="https://ffmpeg.org/releases/ffmpeg-$ffmpeg_version.tar.xz"

python_version="3.13.15"
python_release="20260807"
python_archive="cpython-$python_version+$python_release-aarch64-apple-darwin-install_only_stripped.tar.gz"
python_sha256="dbadb0ffe46f8bace50daaf8a0c5fc6903c003690776da9eb5269e33c856bb53"
python_url="https://github.com/astral-sh/python-build-standalone/releases/download/$python_release/${python_archive/+/%2B}"

mkdir -p "$downloads" "$staging" "$output"

verify_download() {
  local archive_path="$1"
  local expected="$2"
  local actual
  actual="$(shasum -a 256 "$archive_path" | cut -d ' ' -f 1)"
  if [[ "$actual" != "$expected" ]]; then
    echo "SHA-256 verification failed for $archive_path" >&2
    exit 3
  fi
}

download_once() {
  local url="$1"
  local archive_path="$2"
  local sha256="$3"
  if [[ ! -f "$archive_path" ]]; then
    curl --fail --location --progress-bar "$url" --output "$archive_path"
  fi
  verify_download "$archive_path" "$sha256"
}

build_ffmpeg() {
  local archive="$downloads/ffmpeg-$ffmpeg_version.tar.xz"
  local source="$staging/ffmpeg-$ffmpeg_version"
  local install
  install="$(mktemp -d /tmp/AirCiller-FFmpeg.XXXXXX)"
  local package="$staging/ffmpeg"
  local zip_path="$output/ffmpeg-$ffmpeg_version-macos-arm64.zip"

  download_once "$ffmpeg_url" "$archive" "$ffmpeg_sha256"
  rm -rf "$source" "$package"
  tar -xJf "$archive" -C "$staging"
  mkdir -p "$install" "$package/bin" "$package/LICENSES"

  (
    cd "$source"
    ./configure \
      --prefix="$install" \
      --arch=arm64 \
      --target-os=darwin \
      --disable-shared \
      --enable-static \
      --disable-autodetect \
      --enable-zlib \
      --enable-iconv \
      --extra-ldflags=-liconv \
      --enable-pthreads \
      --disable-doc \
      --disable-debug \
      --disable-avdevice \
      --disable-ffplay
    make -j"$(sysctl -n hw.logicalcpu)"
    make install
  )

  cp "$install/bin/ffmpeg" "$install/bin/ffprobe" "$package/bin/"
  strip -x "$package/bin/ffmpeg" "$package/bin/ffprobe"
  cp "$source/COPYING.LGPLv2.1" "$package/LICENSES/FFmpeg-LGPL-2.1.txt"
  printf '%s\n' "$ffmpeg_version" > "$package/VERSION"
  rm -f "$zip_path"
  ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl "$package" "$zip_path"
  rm -rf "$install"
}

build_python() {
  local archive="$downloads/$python_archive"
  local package="$staging/airplay"
  local zip_path="$output/airplay-python-$python_version-macos-arm64.zip"

  download_once "$python_url" "$archive" "$python_sha256"
  rm -rf "$package"
  mkdir -p "$package"
  tar -xzf "$archive" -C "$package"
  "$package/python/bin/python3" -c 'import ssl, sqlite3, zlib'
  printf '%s\n' "$python_version" > "$package/VERSION"
  rm -f "$zip_path"
  ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl "$package" "$zip_path"
}

case "${1:-all}" in
  ffmpeg) build_ffmpeg ;;
  airplay) build_python ;;
  all)
    build_ffmpeg
    build_python
    ;;
  *)
    echo "Usage: $0 [ffmpeg|airplay|all]" >&2
    exit 2
    ;;
esac

for archive in "$output"/*.zip; do
  shasum -a 256 "$archive"
done

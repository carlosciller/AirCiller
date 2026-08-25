#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_path="${1:-$project_dir/.build/AirCiller.app}"
release_dir="$project_dir/.build/releases"

if [[ ! -d "$app_path" ]]; then
    echo "Build AirCiller before packaging an update." >&2
    exit 2
fi

info_plist="$app_path/Contents/Info.plist"
version="$(plutil -extract CFBundleShortVersionString raw "$info_plist")"
build="$(plutil -extract CFBundleVersion raw "$info_plist")"
feed_url="$(plutil -extract SUFeedURL raw "$info_plist")"
public_key="$(plutil -extract SUPublicEDKey raw "$info_plist")"

if [[ "$feed_url" != https://* || -z "$public_key" ]]; then
    echo "The built app does not contain a valid update feed and public key." >&2
    exit 2
fi

archive_path="$release_dir/AirCiller-$version-$build.zip"
mkdir -p "$release_dir"
rm -f "$archive_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"

codesign --verify --deep --strict "$app_path"
echo "$archive_path"

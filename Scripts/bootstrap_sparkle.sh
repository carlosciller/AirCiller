#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
sparkle_version="2.9.6"
sparkle_sha256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"
sparkle_url="https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/Sparkle-$sparkle_version.tar.xz"
download_dir="$project_dir/.build/downloads"
dependencies_dir="$project_dir/.build/dependencies"
archive_path="$download_dir/Sparkle-$sparkle_version.tar.xz"
install_path="$dependencies_dir/Sparkle-$sparkle_version"
staging_path="$dependencies_dir/.Sparkle-$sparkle_version.staging"

if [[ -d "$install_path/Sparkle.framework" \
  && -x "$install_path/bin/generate_keys" \
  && -x "$install_path/bin/generate_appcast" \
  && -x "$install_path/bin/sign_update" ]]; then
    echo "Sparkle $sparkle_version is ready."
    exit 0
fi

mkdir -p "$download_dir" "$dependencies_dir"

archive_is_valid=false
if [[ -f "$archive_path" ]]; then
    current_sha256="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
    [[ "$current_sha256" == "$sparkle_sha256" ]] && archive_is_valid=true
fi

if [[ "$archive_is_valid" != true ]]; then
    rm -f "$archive_path"
    echo "Downloading Sparkle $sparkle_version from the official release…"
    curl \
        --fail \
        --location \
        --progress-bar \
        --proto '=https' \
        --tlsv1.2 \
        --output "$archive_path" \
        "$sparkle_url"
fi

current_sha256="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
if [[ "$current_sha256" != "$sparkle_sha256" ]]; then
    echo "Sparkle archive verification failed." >&2
    exit 1
fi

rm -rf "$staging_path"
mkdir -p "$staging_path"
tar -xJf "$archive_path" -C "$staging_path"

for required_path in \
    "$staging_path/Sparkle.framework" \
    "$staging_path/bin/generate_keys" \
    "$staging_path/bin/generate_appcast" \
    "$staging_path/bin/sign_update" \
    "$staging_path/LICENSE"; do
    if [[ ! -e "$required_path" ]]; then
        echo "The Sparkle distribution is incomplete: $required_path" >&2
        exit 1
    fi
done

rm -rf "$install_path"
mv "$staging_path" "$install_path"
echo "Sparkle $sparkle_version is ready."

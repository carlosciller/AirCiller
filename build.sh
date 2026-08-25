#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
build_dir="$project_dir/.build"
app_path="$build_dir/AirCiller.app"
staged_app_path="$build_dir/AirCiller.staged.app"
previous_app_path="$build_dir/AirCiller.previous.app"
contents_path="$staged_app_path/Contents"
binary_path="$contents_path/MacOS/AirCiller"
generated_resources="$build_dir/generated-resources"
module_cache="$build_dir/module-cache"
vendor_path="$project_dir/VendorPython"
runtime_marker="$vendor_path/.airciller-python-executable"
sparkle_distribution="$build_dir/dependencies/Sparkle-2.9.6"
sparkle_framework="$sparkle_distribution/Sparkle.framework"

if [[ ! -d "$vendor_path" || ! -f "$runtime_marker" ]]; then
  echo "The reproducible Python engine is missing. Run ./Scripts/bootstrap_dependencies.sh." >&2
  exit 2
fi

if [[ ! -d "$sparkle_framework" ]]; then
  echo "Sparkle is missing. Run ./Scripts/bootstrap_sparkle.sh." >&2
  exit 2
fi

sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
swiftc_path="$(xcrun --find swiftc)"

rm -rf "$staged_app_path" "$previous_app_path" "$generated_resources"
mkdir -p \
  "$contents_path/MacOS" \
  "$contents_path/Frameworks" \
  "$contents_path/Resources" \
  "$generated_resources" \
  "$module_cache"

"$swiftc_path" \
  -sdk "$sdk_path" \
  -target arm64-apple-macosx14.0 \
  -module-cache-path "$module_cache" \
  -framework AppKit \
  "$project_dir/Scripts/make_icon.swift" \
  -o "$build_dir/make-icon"
"$build_dir/make-icon" \
  "$generated_resources/AirCiller-1024.png" \
  "$generated_resources/AirCiller.icns"

"$swiftc_path" \
  -sdk "$sdk_path" \
  -target arm64-apple-macosx14.0 \
  -module-cache-path "$module_cache" \
  -parse-as-library \
  -swift-version 6 \
  -warn-concurrency \
  -strict-concurrency=complete \
  -warnings-as-errors \
  -O \
  -Xlinker -dead_strip \
  -Xlinker -rpath \
  -Xlinker @executable_path/../Frameworks \
  -F "$sparkle_distribution" \
  -framework Sparkle \
  -framework SwiftUI \
  -framework AppKit \
  -framework AVKit \
  -framework AVFoundation \
  -framework Network \
  -framework MediaPlayer \
  -framework Vision \
  -framework ImageIO \
  -framework Security \
  -framework UniformTypeIdentifiers \
  "$project_dir"/Sources/*.swift \
  -o "$binary_path"

cp "$project_dir/Info.plist" "$contents_path/Info.plist"
ditto "$sparkle_framework" "$contents_path/Frameworks/Sparkle.framework"
cp "$generated_resources/AirCiller.icns" "$contents_path/Resources/AirCiller.icns"
cp "$generated_resources/AirCiller-1024.png" "$contents_path/Resources/AirCillerArtwork.png"
cp "$project_dir/Scripts/airplay_helper.py" "$contents_path/Resources/AirCillerAirPlay.py"
ditto "$project_dir/Resources/en.lproj" "$contents_path/Resources/en.lproj"
ditto "$project_dir/Resources/es.lproj" "$contents_path/Resources/es.lproj"
mkdir -p "$contents_path/Resources/Legal"
cp "$project_dir/LICENSE" "$contents_path/Resources/Legal/AirCiller-LICENSE.txt"
cp "$project_dir/NOTICE.md" "$contents_path/Resources/Legal/NOTICE.md"
cp "$project_dir/THIRD_PARTY_NOTICES.md" "$contents_path/Resources/Legal/THIRD_PARTY_NOTICES.md"
cp "$project_dir/LICENSES/pyatv-MIT.md" "$contents_path/Resources/Legal/pyatv-MIT.md"
cp "$sparkle_distribution/LICENSE" "$contents_path/Resources/Legal/Sparkle-LICENSE.txt"
ditto "$vendor_path" "$contents_path/Resources/VendorPython"
rm -rf "$contents_path/Resources/VendorPython/bin"
find "$contents_path/Resources/VendorPython" -type d -name __pycache__ -prune -exec rm -rf {} +

codesign --force --sign - "$staged_app_path"
codesign --verify --deep --strict "$staged_app_path"

if [[ -e "$app_path" ]]; then
  mv "$app_path" "$previous_app_path"
fi
if mv "$staged_app_path" "$app_path"; then
  rm -rf "$previous_app_path"
else
  [[ ! -e "$app_path" && -e "$previous_app_path" ]] && mv "$previous_app_path" "$app_path"
  exit 1
fi

echo "$app_path"

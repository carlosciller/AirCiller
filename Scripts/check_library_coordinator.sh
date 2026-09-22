#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
test_dir="$project_dir/.build/tests"
module_cache="$project_dir/.build/test-module-cache"
sparkle_distribution="$project_dir/.build/dependencies/Sparkle-2.9.6"
fixture_uuid="$(uuidgen)"
fixture_app="$test_dir/LibraryCoordinator-$fixture_uuid.app"
fixture_plist="$fixture_app/Contents/Info.plist"
fixture_binary="$fixture_app/Contents/MacOS/LibraryCoordinatorCheck"

if [[ ! -d "$sparkle_distribution/Sparkle.framework" ]]; then
  echo "Sparkle is missing. Run ./Scripts/bootstrap_sparkle.sh." >&2
  exit 2
fi
if [[ -e "$fixture_app" ]]; then
  echo "Refusing to reuse an existing coordinator check bundle." >&2
  exit 2
fi

# Keep the isolated executable as local test evidence. The test removes only its
# own fresh preferences domain; it never reads the installed app's library.
mkdir -p "$fixture_app/Contents/MacOS" "$module_cache"
plutil -create xml1 "$fixture_plist"
plutil -insert CFBundleIdentifier -string "local.airciller.LibraryCoordinatorCheck.$fixture_uuid" "$fixture_plist"
plutil -insert CFBundleName -string "Library Coordinator Check" "$fixture_plist"
plutil -insert CFBundleExecutable -string "LibraryCoordinatorCheck" "$fixture_plist"
plutil -insert CFBundlePackageType -string APPL "$fixture_plist"
plutil -insert LSBackgroundOnly -bool true "$fixture_plist"

# Compile the real coordinator and services without the SwiftUI app entry point
# or views. UI_CHECKS skips stale-buffer cleanup; no media or receiver is opened.
check_sources=("$project_dir"/Sources/*.swift)
for excluded_name in AirCillerApp MainWindowView NativePlaylistTable OpenSubtitlesViews SettingsViews; do
  excluded_source="$project_dir/Sources/$excluded_name.swift"
  check_sources=("${(@)check_sources:#$excluded_source}")
done

xcrun swiftc \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target arm64-apple-macosx14.0 \
  -module-cache-path "$module_cache" \
  -parse-as-library \
  -swift-version 6 \
  -warn-concurrency \
  -strict-concurrency=complete \
  -warnings-as-errors \
  -D AIRCILLER_UI_CHECKS \
  -F "$sparkle_distribution" \
  -framework Sparkle -framework SwiftUI -framework AppKit \
  -framework AVKit -framework AVFoundation -framework Network \
  -framework MediaPlayer -framework Vision -framework ImageIO \
  -framework Security -framework UniformTypeIdentifiers \
  -Xlinker -rpath -Xlinker "$sparkle_distribution" \
  "${check_sources[@]}" \
  "$project_dir/Tests/LibraryCoordinatorSmokeTest.swift" \
  -o "$fixture_binary"

"$fixture_binary" --skip-device-scan

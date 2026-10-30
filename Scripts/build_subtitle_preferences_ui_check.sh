#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
fixture_uuid="$(uuidgen)"
fixture_app="$project_dir/.build/tests/SubtitlePreferences-$fixture_uuid.app"
sparkle="$project_dir/.build/dependencies/Sparkle-2.9.6"
mkdir -p "$fixture_app/Contents/MacOS" "$fixture_app/Contents/Resources"
plutil -create xml1 "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string "local.airciller.SubtitlePreferencesCheck.$fixture_uuid" "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleName -string "AirCiller Subtitle Preferences Check" "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleExecutable -string SubtitlePreferencesCheck "$fixture_app/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$fixture_app/Contents/Info.plist"
cp -R "$project_dir/Resources/en.lproj" "$project_dir/Resources/es.lproj" "$fixture_app/Contents/Resources/"
# Reuse the alternate native-UI entry-point flag; no normal-app main is compiled.
xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target arm64-apple-macosx14.0 -module-cache-path "$project_dir/.build/test-module-cache" \
  -parse-as-library -swift-version 6 -strict-concurrency=complete -warn-concurrency -warnings-as-errors \
  -D AIRCILLER_UI_CHECKS -D AIRCILLER_LIBRARY_UI_CHECKS \
  -F "$sparkle" -framework Sparkle -framework SwiftUI -framework AppKit \
  -framework AVKit -framework AVFoundation -framework Network -framework MediaPlayer \
  -framework Vision -framework ImageIO -framework Security -framework UniformTypeIdentifiers \
  -Xlinker -rpath -Xlinker "$sparkle" \
  "$project_dir"/Sources/*.swift "$project_dir/Tests/SubtitlePreferencesUICheck.swift" \
  -o "$fixture_app/Contents/MacOS/SubtitlePreferencesCheck"
codesign --force --sign - "$fixture_app"
echo "$fixture_app"

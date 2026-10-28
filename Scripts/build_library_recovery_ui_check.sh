#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
fixture_uuid="$(uuidgen)"
fixture_app="$project_dir/.build/tests/RecoveryUI-$fixture_uuid.app"
sparkle="$project_dir/.build/dependencies/Sparkle-2.9.6"
mkdir -p "$fixture_app/Contents/MacOS" "$fixture_app/Contents/Resources"
plutil -create xml1 "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string "local.airciller.RecoveryUICheck.$fixture_uuid" "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleName -string "AirCiller Recovery Check" "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleExecutable -string RecoveryUICheck "$fixture_app/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$fixture_app/Contents/Info.plist"
cp -R "$project_dir/Resources/en.lproj" "$project_dir/Resources/es.lproj" "$fixture_app/Contents/Resources/"
xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target arm64-apple-macosx14.0 -module-cache-path "$project_dir/.build/test-module-cache" \
  -parse-as-library -swift-version 6 -strict-concurrency=complete -warn-concurrency -warnings-as-errors \
  -D AIRCILLER_UI_CHECKS -D AIRCILLER_LIBRARY_UI_CHECKS \
  -F "$sparkle" -framework Sparkle -framework SwiftUI -framework AppKit \
  -framework AVKit -framework AVFoundation -framework Network -framework MediaPlayer \
  -framework Vision -framework ImageIO -framework Security -framework UniformTypeIdentifiers \
  -Xlinker -rpath -Xlinker "$sparkle" \
  "$project_dir"/Sources/*.swift "$project_dir/Tests/LibraryRecoveryUICheck.swift" \
  -o "$fixture_app/Contents/MacOS/RecoveryUICheck"
codesign --force --sign - "$fixture_app"
echo "$fixture_app"

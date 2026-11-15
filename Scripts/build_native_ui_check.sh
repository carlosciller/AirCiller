#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
case "${1:-}" in
  chapter-skip) fixture_type=ChapterSkip; fixture_prefix=ChapterSkip; fixture_name="Chapter Check" ;;
  playback-information) fixture_type=PreparedPlaybackInformation; fixture_prefix=PlaybackInformation; fixture_name="Information Check" ;;
  episode-presentation) fixture_type=EpisodePresentation; fixture_prefix=EpisodePresentation; fixture_name="Episode Check" ;;
  season-continuation) fixture_type=SeasonContinuation; fixture_prefix=SeasonContinuation; fixture_name="Season Check" ;;
  subtitle-preferences) fixture_type=SubtitlePreferences; fixture_prefix=SubtitlePreferences; fixture_name="Subtitle Preferences Check" ;;
  library-recovery) fixture_type=RecoveryUI; fixture_prefix=RecoveryUI; fixture_name="Recovery Check" ;;
  *) echo 'Usage: build_native_ui_check.sh chapter-skip|season-continuation|playback-information|episode-presentation|subtitle-preferences|library-recovery' >&2; exit 2 ;;
esac
fixture_source="${fixture_type}UICheck"
[[ "$1" != library-recovery ]] || fixture_source=LibraryRecoveryUICheck
fixture_uuid="$(uuidgen)"
fixture_app="$project_dir/.build/tests/$fixture_prefix-$fixture_uuid.app"
sparkle="$project_dir/.build/dependencies/Sparkle-2.9.6"
mkdir -p "$fixture_app/Contents/MacOS" "$fixture_app/Contents/Resources"
plutil -create xml1 "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string "local.airciller.${fixture_type}Check.$fixture_uuid" "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleName -string "AirCiller $fixture_name" "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleExecutable -string "${fixture_type}Check" "$fixture_app/Contents/Info.plist"
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
  "$project_dir"/Sources/*.swift "$project_dir/Tests/$fixture_source.swift" \
  -o "$fixture_app/Contents/MacOS/${fixture_type}Check"
codesign --force --sign - "$fixture_app"
echo "$fixture_app"

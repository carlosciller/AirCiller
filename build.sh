#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
build_dir="$project_dir/.build"
app_path="$build_dir/AirCiller.app"
staged_app_path="$build_dir/AirCiller.staged.app"
previous_app_path="$build_dir/AirCiller.previous.app"
extra_swift_arguments=()
extra_swift_sources=()
extra_link_inputs=()
test_icon_arguments=()
is_auxiliary_build=false
shortcuts_enabled=true
app_intents_arguments=()
if [[ "${1:-}" == "--playback-checks" && $# == 1 ]]; then
  app_path="$build_dir/AirCiller Playback Checks.app"
  staged_app_path="$build_dir/AirCiller Playback Checks.staged.app"
  previous_app_path="$build_dir/AirCiller Playback Checks.previous.app"
  extra_swift_arguments=(
    -D AIRCILLER_PLAYBACK_CHECKS
    -import-objc-header "$project_dir/Tests/PlaybackChecks/KeychainInteraction.h"
  )
  extra_link_inputs=("$build_dir/playback-keychain-interaction.o")
  extra_swift_sources=(
    "$project_dir/Tests/PlaybackChecks/PlaybackCheckModel.swift"
    "$project_dir/Tests/PlaybackChecks/PlaybackCheckRunner.swift"
    "$project_dir/Tests/PlaybackChecks/PlaybackCheckCacheEvidence.swift"
    "$project_dir/Tests/PlaybackChecks/PlaybackCheckScenarios.swift"
    "$project_dir/Tests/PlaybackChecks/BitmapCancellationCheck.swift"
  )
  is_auxiliary_build=true
  shortcuts_enabled=false
  test_icon_arguments=(--test)
elif [[ "${1:-}" == "--candidate" && ( $# == 1 || ( $# == 2 && "${2:-}" == "--without-shortcuts" ) ) ]]; then
  app_path="$build_dir/AirCiller Test.app"
  staged_app_path="$build_dir/AirCiller Test.staged.app"
  previous_app_path="$build_dir/AirCiller Test.previous.app"
  extra_swift_arguments=(-D AIRCILLER_UI_CHECKS)
  is_auxiliary_build=true
  test_icon_arguments=(--test)
  if [[ "${2:-}" == "--without-shortcuts" ]]; then
    extra_swift_arguments+=(-D AIRCILLER_NO_SHORTCUTS)
    shortcuts_enabled=false
    echo "Building a UI-only candidate without Apple Shortcuts. This is not a Shortcuts release candidate." >&2
  fi
elif [[ $# != 0 ]]; then
  echo "Usage: ./build.sh [--playback-checks | --candidate [--without-shortcuts]]" >&2
  exit 2
fi
app_intents_processor=""
if $shortcuts_enabled; then
  if ! app_intents_processor="$(xcrun --find appintentsmetadataprocessor 2>/dev/null)"; then
    echo "Apple Shortcuts metadata requires the full Xcode tools. Command Line Tools alone cannot package the actions." >&2
    echo "Select Xcode through DEVELOPER_DIR, or use --candidate --without-shortcuts only for local UI checks." >&2
    exit 2
  fi
fi
signing_identity="$(/bin/zsh "$project_dir/Scripts/signing_identity.sh")"
credential_service_path=""
local_signing_options=()
if [[ "$signing_identity" != "-" ]]; then
  credential_service_path="$(/bin/zsh "$project_dir/Scripts/build_credential_service.sh" --verify)"
  local_signing_options=(--options runtime --entitlements "$project_dir/CredentialService/Client.entitlements")
fi
contents_path="$staged_app_path/Contents"
binary_path="$contents_path/MacOS/AirCiller"
generated_resources="$build_dir/generated-resources"
module_cache="$build_dir/module-cache"
vendor_path="$project_dir/VendorPython"
runtime_marker="$vendor_path/.airciller-python-executable"
sparkle_distribution="$build_dir/dependencies/Sparkle-2.9.6"
sparkle_framework="$sparkle_distribution/Sparkle.framework"
engine_path="$build_dir/dependencies/AirCillerEngine-ffmpeg-9.0.1-python-3.13.15"
app_intents_source="$project_dir/Sources/ShortcutsIntents.swift"
app_intents_intermediates="$build_dir/app-intents/${app_path:t:r}"

if [[ ! -d "$vendor_path" || ! -f "$runtime_marker" ]]; then
  echo "The reproducible Python engine is missing. Run ./Scripts/bootstrap_dependencies.sh." >&2
  exit 2
fi

if [[ ! -d "$sparkle_framework" ]]; then
  echo "Sparkle is missing. Run ./Scripts/bootstrap_sparkle.sh." >&2
  exit 2
fi

if [[ ! -x "$engine_path/ffmpeg/bin/ffmpeg" \
  || ! -x "$engine_path/ffmpeg/bin/ffprobe" \
  || ! -x "$engine_path/airplay/python/bin/python3" ]]; then
  echo "The bundled playback engine is missing. Run ./Scripts/bootstrap_engine.sh." >&2
  exit 2
fi

sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
swiftc_path="$(xcrun --find swiftc)"

if [[ ${#extra_link_inputs[@]} != 0 ]]; then
  mkdir -p "$build_dir"
  xcrun clang -target arm64-apple-macosx14.0 -Wall -Wextra -Werror -c \
    "$project_dir/Tests/PlaybackChecks/KeychainInteraction.c" -o "${extra_link_inputs[1]}"
fi

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
  "${test_icon_arguments[@]}" \
  "$generated_resources/AirCiller-1024.png" \
  "$generated_resources/AirCiller.icns"

if $shortcuts_enabled; then
  "$engine_path/airplay/python/bin/python3" -B "$project_dir/Scripts/app_intents_metadata.py" prepare \
    --source "$app_intents_source" --intermediates "$app_intents_intermediates"
  app_intents_arguments=(
    -emit-const-values
    -output-file-map "$app_intents_intermediates/output-map.json"
    -Xfrontend -const-gather-protocols-file
    -Xfrontend "$app_intents_intermediates/protocols.json"
    -framework AppIntents
  )
fi

"$swiftc_path" \
  -sdk "$sdk_path" \
  -target arm64-apple-macosx14.0 \
  -module-cache-path "$module_cache" \
  -parse-as-library \
  -module-name AirCiller \
  -swift-version 6 \
  -warn-concurrency \
  -strict-concurrency=complete \
  -warnings-as-errors \
  "${extra_swift_arguments[@]}" \
  "${app_intents_arguments[@]}" \
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
  "${extra_swift_sources[@]}" \
  "${extra_link_inputs[@]}" \
  -o "$binary_path"

cp "$project_dir/Info.plist" "$contents_path/Info.plist"
if [[ -n "$credential_service_path" ]]; then
  mkdir -p "$contents_path/XPCServices"
  ditto "$credential_service_path" "$contents_path/XPCServices/AirCillerCredentialService.xpc"
  plutil -insert ACCredentialServiceRequired -bool true "$contents_path/Info.plist"
  plutil -insert ACCredentialServiceClientVersion -string 1 "$contents_path/Info.plist"
fi
if $is_auxiliary_build; then
  # Both internal tools use the already allowlisted credential-client identity.
  # Never run them concurrently. Do not broaden the credential service policy.
  plutil -replace CFBundleIdentifier -string local.carlosciller.AirCiller.PlaybackChecks "$contents_path/Info.plist"
  plutil -replace CFBundleName -string "${app_path:t:r}" "$contents_path/Info.plist"
  plutil -replace CFBundleDisplayName -string "${app_path:t:r}" "$contents_path/Info.plist"
  plutil -insert ACDevelopmentBuild -bool true "$contents_path/Info.plist"
  plutil -replace SUEnableAutomaticChecks -bool false "$contents_path/Info.plist"
  plutil -replace SUAutomaticallyUpdate -bool false "$contents_path/Info.plist"
  for key in SUFeedURL SUPublicEDKey CFBundleDocumentTypes CFBundleURLTypes; do
    if plutil -extract "$key" raw "$contents_path/Info.plist" >/dev/null 2>&1; then
      plutil -remove "$key" "$contents_path/Info.plist"
    fi
  done
fi
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
mkdir -p "$contents_path/Resources/Engine"
ditto "$engine_path/ffmpeg" "$contents_path/Resources/Engine/ffmpeg"
ditto "$engine_path/airplay" "$contents_path/Resources/Engine/airplay"
printf '%s\n' "Engine/airplay/python/bin/python3" \
  > "$contents_path/Resources/VendorPython/.airciller-python-executable"

if $shortcuts_enabled; then
  xcode_build_version="$(xcodebuild -version | awk '/^Build version / { print $3; exit }')"
  if [[ -z "$xcode_build_version" ]]; then
    echo "Could not identify the Xcode build for App Intents metadata." >&2
    exit 2
  fi
  "$engine_path/airplay/python/bin/python3" -B "$project_dir/Scripts/app_intents_metadata.py" extract \
    --source "$app_intents_source" --intermediates "$app_intents_intermediates" \
    --app "$staged_app_path" --processor "$app_intents_processor" \
    --sdk "$sdk_path" --toolchain "${swiftc_path:A:h:h:h}" --xcode-version "$xcode_build_version"
  plutil -insert ACShortcutsAvailable -bool true "$contents_path/Info.plist"
else
  plutil -insert ACShortcutsAvailable -bool false "$contents_path/Info.plist"
fi

codesign --force --sign "$signing_identity" "${local_signing_options[@]}" "$staged_app_path"
codesign --verify --deep --strict "$staged_app_path"
"$engine_path/airplay/python/bin/python3" -B "$project_dir/Scripts/check_bundle_size.py" "$staged_app_path"

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

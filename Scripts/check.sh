#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
build_dir="$project_dir/.build"
test_dir="$build_dir/tests"
module_cache="$build_dir/test-module-cache"
swiftc_path="$(xcrun --find swiftc)"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"

if [[ ! -f "$project_dir/VendorPython/.airciller-python-executable" ]]; then
  echo "VendorPython is missing. Run ./Scripts/bootstrap_dependencies.sh." >&2
  exit 2
fi

if [[ ! -d "$project_dir/.build/dependencies/Sparkle-2.9.6/Sparkle.framework" ]]; then
  echo "Sparkle is missing. Run ./Scripts/bootstrap_sparkle.sh." >&2
  exit 2
fi

mkdir -p "$test_dir" "$module_cache" "$build_dir/python-cache"

common_swift_arguments=(
  -sdk "$sdk_path"
  -target arm64-apple-macosx14.0
  -module-cache-path "$module_cache"
  -parse-as-library
  -swift-version 6
  -warn-concurrency
  -strict-concurrency=complete
  -warnings-as-errors
)

compile_and_run() {
  local name="$1"
  shift
  "$swiftc_path" "${common_swift_arguments[@]}" "$@" -o "$test_dir/$name"
  "$test_dir/$name"
}

plutil -lint "$project_dir/Info.plist"
plutil -lint \
  "$project_dir/Resources/en.lproj/Localizable.strings" \
  "$project_dir/Resources/es.lproj/Localizable.strings" \
  "$project_dir/Resources/en.lproj/InfoPlist.strings" \
  "$project_dir/Resources/es.lproj/InfoPlist.strings"
xcrun swift-format lint --strict --recursive \
  "$project_dir/Sources" \
  "$project_dir/Tests" \
  "$project_dir/Scripts/make_icon.swift"

compile_and_run authorization \
  "$project_dir/Sources/AirPlayAuthorizationRetryPolicy.swift" \
  "$project_dir/Tests/AirPlayAuthorizationRetryPolicySmokeTest.swift"
compile_and_run pairing-intent \
  "$project_dir/Sources/AirPlayPairingIntent.swift" \
  "$project_dir/Tests/AirPlayPairingIntentSmokeTest.swift"
compile_and_run launch-options \
  "$project_dir/Sources/AirCillerLaunchOptions.swift" \
  "$project_dir/Tests/LaunchOptionsSmokeTest.swift"
compile_and_run update-configuration \
  "$project_dir/Sources/UpdateConfiguration.swift" \
  "$project_dir/Tests/UpdateConfigurationSmokeTest.swift"
compile_and_run power-assertion \
  "$project_dir/Sources/Localization.swift" \
  "$project_dir/Sources/PlaybackPowerAssertion.swift" \
  "$project_dir/Tests/PlaybackPowerAssertionSmokeTest.swift"
compile_and_run cancellable-process \
  "$project_dir/Sources/CancellableProcess.swift" \
  "$project_dir/Tests/CancellableProcessSmokeTest.swift"
compile_and_run component-manager \
  "$project_dir/Sources/Localization.swift" \
  "$project_dir/Sources/ProcessDataBuffer.swift" \
  "$project_dir/Sources/CancellableProcess.swift" \
  "$project_dir/Sources/ComponentManager.swift" \
  "$project_dir/Tests/ComponentManagerSmokeTest.swift"
compile_and_run local-network-route \
  "$project_dir/Sources/LocalNetworkRoute.swift" \
  "$project_dir/Tests/LocalNetworkRouteSmokeTest.swift"
compile_and_run storage \
  "$project_dir/Sources/Localization.swift" \
  "$project_dir/Sources/AirCillerError.swift" \
  "$project_dir/Sources/AirCillerStorage.swift" \
  "$project_dir/Tests/AirCillerStorageSmokeTest.swift"
compile_and_run subtitle-ocr-text \
  "$project_dir/Sources/SubtitleOCRTextNormalizer.swift" \
  "$project_dir/Tests/SubtitleOCRTextNormalizerSmokeTest.swift"
compile_and_run ass-subtitles \
  "$project_dir/Sources/ASSSubtitleConverter.swift" \
  "$project_dir/Tests/ASSSubtitleConverterSmokeTest.swift"
compile_and_run localization \
  "$project_dir/Tests/LocalizationSmokeTest.swift"
compile_and_run track-metadata \
  "$project_dir/Sources/Localization.swift" \
  "$project_dir/Sources/MediaModels.swift" \
  "$project_dir/Tests/TrackMetadataSmokeTest.swift"
compile_and_run http-server \
  -framework Network \
  "$project_dir/Sources/Localization.swift" \
  "$project_dir/Sources/HTTPServerTelemetry.swift" \
  "$project_dir/Sources/LocalNetworkRoute.swift" \
  "$project_dir/Sources/LocalHTTPServer.swift" \
  "$project_dir/Tests/HTTPServerSmokeTest.swift"

python_path="$(< "$project_dir/VendorPython/.airciller-python-executable")"
PYTHONPATH="$project_dir/VendorPython" \
PYTHONPYCACHEPREFIX="$build_dir/python-cache" \
  "$python_path" "$project_dir/Tests/AirPlayHelperSmokeTest.py"

"$project_dir/Scripts/check_publication.sh"
"$project_dir/build.sh"

test -f "$project_dir/.build/AirCiller.app/Contents/Resources/en.lproj/Localizable.strings"
test -f "$project_dir/.build/AirCiller.app/Contents/Resources/es.lproj/Localizable.strings"
test -d "$project_dir/.build/AirCiller.app/Contents/Frameworks/Sparkle.framework"
test -f "$project_dir/.build/AirCiller.app/Contents/Resources/Legal/Sparkle-LICENSE.txt"
otool -L "$project_dir/.build/AirCiller.app/Contents/MacOS/AirCiller" | \
  rg -q '@rpath/Sparkle.framework/'
codesign --verify --deep --strict "$project_dir/.build/AirCiller.app"

echo "AirCiller local checks: OK"

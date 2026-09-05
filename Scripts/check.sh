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

engine_path="$project_dir/.build/dependencies/AirCillerEngine-ffmpeg-9.0.1-python-3.13.15"
if [[ ! -x "$engine_path/ffmpeg/bin/ffmpeg" \
  || ! -x "$engine_path/ffmpeg/bin/ffprobe" \
  || ! -x "$engine_path/airplay/python/bin/python3" ]]; then
  echo "The bundled playback engine is missing. Run ./Scripts/bootstrap_engine.sh." >&2
  exit 2
fi

mkdir -p "$test_dir" "$module_cache" "$build_dir/python-cache"

"$project_dir/Scripts/requirements_lock.sh" check

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
compile_and_run pairing-lifecycle \
  "$project_dir/Sources/AirPlayPairingLifecycle.swift" \
  "$project_dir/Tests/AirPlayPairingLifecycleSmokeTest.swift"
compile_and_run authorization-preflight \
  "$project_dir/Sources/PlaybackAuthorizationPreflight.swift" \
  "$project_dir/Tests/PlaybackAuthorizationPreflightSmokeTest.swift"
compile_and_run seek-reconciliation \
  "$project_dir/Sources/AirPlaySeekReconciliation.swift" \
  "$project_dir/Tests/AirPlaySeekReconciliationSmokeTest.swift"
compile_and_run helper-command-writer \
  "$project_dir/Sources/HelperCommandWriter.swift" \
  "$project_dir/Tests/HelperCommandWriterSmokeTest.swift"
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
compile_and_run process-buffer \
  "$project_dir/Sources/ProcessDataBuffer.swift" \
  "$project_dir/Tests/ProcessDataBufferSmokeTest.swift"
compile_and_run captured-process \
  "$project_dir/Sources/ProcessDataBuffer.swift" \
  "$project_dir/Sources/CancellableProcess.swift" \
  "$project_dir/Sources/CapturedProcess.swift" \
  "$project_dir/Tests/CapturedProcessSmokeTest.swift"
compile_and_run credential-store \
  -framework Security \
  "$project_dir/Sources/AirPlayCredentialStore.swift" \
  "$project_dir/Tests/AirPlayCredentialStoreSmokeTest.swift"
compile_and_run opensubtitles-credential-store \
  -framework Security \
  "$project_dir/Sources/OpenSubtitlesCredentialStore.swift" \
  "$project_dir/Tests/OpenSubtitlesCredentialStoreSmokeTest.swift"
compile_and_run opensubtitles-service \
  -framework Security \
  "$project_dir/Sources/Localization.swift" \
  "$project_dir/Sources/AirCillerError.swift" \
  "$project_dir/Sources/AirCillerStorage.swift" \
  "$project_dir/Sources/OpenSubtitlesCredentialStore.swift" \
  "$project_dir/Sources/BoundedHTTPResponse.swift" \
  "$project_dir/Sources/OpenSubtitlesService.swift" \
  "$project_dir/Tests/OpenSubtitlesServiceSmokeTest.swift"
compile_and_run bounded-http-response \
  "$project_dir/Sources/BoundedHTTPResponse.swift" \
  "$project_dir/Tests/BoundedHTTPResponseSmokeTest.swift"
compile_and_run airplay-runtime-probe \
  "$project_dir/Sources/AirPlayRuntimeProbe.swift" \
  "$project_dir/Tests/AirPlayRuntimeProbeSmokeTest.swift"
compile_and_run bundled-engine \
  "$project_dir/Sources/BundledEngine.swift" \
  "$project_dir/Tests/BundledEngineSmokeTest.swift"
compile_and_run media-analysis-tasks \
  "$project_dir/Sources/MediaAnalysisTasks.swift" \
  "$project_dir/Tests/MediaAnalysisTasksSmokeTest.swift"
compile_and_run component-manager \
  "$project_dir/Sources/Localization.swift" \
  "$project_dir/Sources/ProcessDataBuffer.swift" \
  "$project_dir/Sources/CancellableProcess.swift" \
  "$project_dir/Sources/CapturedProcess.swift" \
  "$project_dir/Sources/AirPlayRuntimeProbe.swift" \
  "$project_dir/Sources/BundledEngine.swift" \
  "$project_dir/Sources/DiagnosticsReport.swift" \
  "$project_dir/Sources/ManagedComponentModels.swift" \
  "$project_dir/Sources/ComponentManager.swift" \
  "$project_dir/Tests/ComponentManagerSmokeTest.swift"
compile_and_run history-store \
  "$project_dir/Sources/Localization.swift" \
  "$project_dir/Sources/MediaModels.swift" \
  "$project_dir/Sources/HistoryStore.swift" \
  "$project_dir/Tests/HistoryStoreSmokeTest.swift"
compile_and_run local-network-route \
  "$project_dir/Sources/LocalNetworkRoute.swift" \
  "$project_dir/Tests/LocalNetworkRouteSmokeTest.swift"
compile_and_run network-address-identity \
  "$project_dir/Sources/NetworkAddressIdentity.swift" \
  "$project_dir/Tests/NetworkAddressIdentitySmokeTest.swift"
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
compile_and_run vod-command-builder \
  "$project_dir/Sources/Localization.swift" \
  "$project_dir/Sources/MediaModels.swift" \
  "$project_dir/Sources/VODCommandBuilder.swift" \
  "$project_dir/Tests/VODCommandBuilderSmokeTest.swift"
compile_and_run attached-artwork-probe \
  "$project_dir/Sources/Localization.swift" \
  "$project_dir/Sources/AirCillerError.swift" \
  "$project_dir/Sources/ProcessDataBuffer.swift" \
  "$project_dir/Sources/CancellableProcess.swift" \
  "$project_dir/Sources/ManagedComponentModels.swift" \
  "$project_dir/Sources/BundledEngine.swift" \
  "$project_dir/Sources/MediaModels.swift" \
  "$project_dir/Sources/MediaProbeService.swift" \
  "$project_dir/Tests/AttachedArtworkProbeSmokeTest.swift"
compile_and_run diagnostics-report \
  "$project_dir/Sources/DiagnosticsReport.swift" \
  "$project_dir/Tests/DiagnosticsReportSmokeTest.swift"
compile_and_run media-probe-validation \
  "$project_dir/Sources/Localization.swift" \
  "$project_dir/Sources/AirCillerError.swift" \
  "$project_dir/Sources/ProcessDataBuffer.swift" \
  "$project_dir/Sources/CancellableProcess.swift" \
  "$project_dir/Sources/BundledEngine.swift" \
  "$project_dir/Sources/MediaModels.swift" \
  "$project_dir/Sources/MediaProbeService.swift" \
  "$project_dir/Tests/MediaProbeValidationSmokeTest.swift"
compile_and_run stream-diagnostics \
  "$project_dir/Sources/Localization.swift" \
  "$project_dir/Sources/AirCillerError.swift" \
  "$project_dir/Sources/ProcessDataBuffer.swift" \
  "$project_dir/Sources/CancellableProcess.swift" \
  "$project_dir/Sources/BundledEngine.swift" \
  "$project_dir/Sources/MediaModels.swift" \
  "$project_dir/Sources/MediaProbeService.swift" \
  "$project_dir/Sources/VODBuildProcess.swift" \
  "$project_dir/Sources/StreamDiagnostics.swift" \
  "$project_dir/Sources/SubtitleService.swift" \
  "$project_dir/Sources/ASSSubtitleConverter.swift" \
  "$project_dir/Sources/PGSSubtitleConverter.swift" \
  "$project_dir/Sources/SubtitleOCRService.swift" \
  "$project_dir/Sources/SubtitleOCRTextNormalizer.swift" \
  "$project_dir/Sources/AirCillerStorage.swift" \
  "$project_dir/Tests/StreamDiagnosticsSmokeTest.swift"
compile_and_run http-server \
  -framework Network \
  "$project_dir/Sources/Localization.swift" \
  "$project_dir/Sources/HTTPServerTelemetry.swift" \
  "$project_dir/Sources/LocalNetworkRoute.swift" \
  "$project_dir/Sources/NetworkAddressIdentity.swift" \
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
test -x "$project_dir/.build/AirCiller.app/Contents/Resources/Engine/ffmpeg/bin/ffmpeg"
test -x "$project_dir/.build/AirCiller.app/Contents/Resources/Engine/ffmpeg/bin/ffprobe"
test -x "$project_dir/.build/AirCiller.app/Contents/Resources/Engine/airplay/python/bin/python3"
test "$(plutil -extract ACBundledEngineRequired raw "$project_dir/.build/AirCiller.app/Contents/Info.plist")" = "true"
test -f "$project_dir/.build/AirCiller.app/Contents/Resources/Engine/ffmpeg/LICENSES/FFmpeg-LGPL-2.1.txt"
test -f "$project_dir/.build/AirCiller.app/Contents/Resources/Engine/airplay/python/lib/python3.13/LICENSE.txt"
test "$(< "$project_dir/.build/AirCiller.app/Contents/Resources/VendorPython/.airciller-python-executable")" \
  = "Engine/airplay/python/bin/python3"
test -d "$project_dir/.build/AirCiller.app/Contents/Frameworks/Sparkle.framework"
test -f "$project_dir/.build/AirCiller.app/Contents/Resources/Legal/Sparkle-LICENSE.txt"
otool -L "$project_dir/.build/AirCiller.app/Contents/MacOS/AirCiller" | \
  grep -Eq '@rpath/Sparkle.framework/'
codesign --verify --deep --strict "$project_dir/.build/AirCiller.app"

echo "AirCiller local checks: OK"

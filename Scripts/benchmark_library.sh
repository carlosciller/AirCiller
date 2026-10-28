#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
if [[ "${AIRCILLER_TEST_STORAGE_CHILD:-}" != "$project_dir/Scripts/benchmark_library.sh" ]]; then
  exec python3 "$project_dir/Scripts/test_storage.py" run -- "$project_dir/Scripts/benchmark_library.sh" "$@"
fi
if (( $# < 1 )); then
  echo 'Usage: zsh Scripts/benchmark_library.sh /absolute/movie ... | --links-only | --self-test' >&2
  exit 2
fi
run_dir="$(mktemp -d "$project_dir/.build/startup-benchmark/measurement-library-XXXXXX")"
python3 "$project_dir/Scripts/test_storage.py" register "$run_dir"
engine="$project_dir/.build/dependencies/AirCillerEngine-ffmpeg-9.0.1-python-3.13.15"
app="$run_dir/measure.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
ln -s "$engine" "$app/Contents/Resources/Engine"
plutil -create xml1 "$app/Contents/Info.plist"
plutil -insert ACBundledEngineRequired -bool YES "$app/Contents/Info.plist"
names=(Localization AirCillerError ProcessDataBuffer CancellableProcess BundledEngine MediaModels
 MediaProbeService ExternalVobSub VODBuildProcess VODCommandBuilder StreamDiagnostics SubtitleService
 ASSSubtitleConverter PGSSubtitleConverter SubtitleOCRService SubtitleOCRTextNormalizer AirCillerStorage
 HDRConfigurationInjector HLSAudioTimeline HLSAudioTimelineInfo CapturedProcess PreparedMediaCache
 HLSPreparationService PlaybackStartupTrace)
sources=()
for name in "${names[@]}"; do sources+=("$project_dir/Sources/$name.swift"); done
xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target arm64-apple-macosx14.0 \
 -O -parse-as-library -swift-version 6 -warn-concurrency -strict-concurrency=complete -warnings-as-errors \
 "${sources[@]}" "$project_dir/Tests/HLSPreparationPerformanceBenchmark.swift" \
 -o "$app/Contents/MacOS/measure"
git -C "$project_dir" rev-parse HEAD > "$run_dir/revision.txt"
shasum -a 256 "${sources[@]}" "$project_dir/Tests/HLSPreparationPerformanceBenchmark.swift" \
 "$engine/ffmpeg/bin/ffmpeg" "$engine/ffmpeg/bin/ffprobe" > "$run_dir/sources.txt"
xcrun swiftc --version > "$run_dir/compiler.txt"
sw_vers > "$run_dir/system.txt"
index=0
"$app/Contents/MacOS/measure" cache-links "$run_dir/cache-links"
if [[ "$1" == --links-only && $# == 1 ]]; then
  echo "$run_dir"
  exit 0
fi
if [[ "$1" == --self-test && $# == 1 ]]; then
  "$app/Contents/MacOS/measure" fixture "$run_dir/fixture" "$engine/ffmpeg/bin/ffmpeg" /opt/homebrew/bin/ffmpeg
  set -- "$run_dir/fixture/fixture.mkv"
fi
for movie in "$@"; do
  [[ "$movie" == /* && -f "$movie" && ! -L "$movie" ]] || exit 2
  # Private reproducibility record, inside the ignored and retained run directory.
  stat -f '%d %i %z %m %c %N' "$movie" > "$run_dir/input-$index.txt"
  "$app/Contents/MacOS/measure" library "$run_dir/media-$index" "$movie" 3
  stat -f '%d %i %z %m %c %N' "$movie" > "$run_dir/input-$index-after.txt"
  cmp "$run_dir/input-$index.txt" "$run_dir/input-$index-after.txt"
  (( index += 1 ))
done
echo "$run_dir"

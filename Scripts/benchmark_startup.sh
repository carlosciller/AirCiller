#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
repetitions="${1:-5}"
if [[ "$repetitions" != [1-9] ]]; then
  echo "Usage: $0 [repetitions: 1-9, default 5]" >&2
  exit 2
fi
baseline_revision="558b2350cec9414cfb1d8aca72a693f5412497ef"
engine_root="$project_dir/.build/dependencies/AirCillerEngine-ffmpeg-9.0.1-python-3.13.15"
ffmpeg="$engine_root/ffmpeg/bin/ffmpeg"
ffprobe="$engine_root/ffmpeg/bin/ffprobe"
fixture_encoder="${AIRCILLER_FIXTURE_FFMPEG:-/opt/homebrew/bin/ffmpeg}"
if [[ ! -x "$ffmpeg" || ! -x "$ffprobe" ]]; then
  echo "Pinned playback engine is missing; this benchmark never installs dependencies." >&2
  exit 2
fi
if [[ "$fixture_encoder" != /* || ! -x "$fixture_encoder" ]]; then
  echo "Set AIRCILLER_FIXTURE_FFMPEG to an installed FFmpeg with libx264 for synthetic fixtures only." >&2
  exit 2
fi
benchmark_root="$project_dir/.build/startup-benchmark"
mkdir -p "$benchmark_root"
run_dir="$(mktemp -d "$benchmark_root/run.XXXXXX")"
baseline_dir="$run_dir/baseline-sources"
mkdir -p "$baseline_dir"
"$fixture_encoder" -version > "$run_dir/fixture-encoder.txt"
"$fixture_encoder" -hide_banner -encoders > "$run_dir/fixture-encoders.txt"
if ! /usr/bin/grep -q 'ffmpeg version' "$run_dir/fixture-encoder.txt" \
  || ! /usr/bin/grep -q ' libx264 ' "$run_dir/fixture-encoders.txt"; then
  echo "Fixture encoder must be FFmpeg with libx264; no dependencies will be installed." >&2
  exit 2
fi
common_names=(
  Localization AirCillerError ProcessDataBuffer CancellableProcess BundledEngine
  MediaModels MediaProbeService ExternalVobSub VODBuildProcess VODCommandBuilder
  StreamDiagnostics SubtitleService ASSSubtitleConverter PGSSubtitleConverter
  SubtitleOCRService SubtitleOCRTextNormalizer AirCillerStorage HDRConfigurationInjector
)
baseline_sources=()
current_sources=()
for name in "${common_names[@]}"; do
  git -C "$project_dir" show "$baseline_revision:Sources/$name.swift" > "$baseline_dir/$name.swift"
  baseline_sources+=("$baseline_dir/$name.swift")
  current_sources+=("$project_dir/Sources/$name.swift")
done
common_arguments=(
  -sdk "$(xcrun --sdk macosx --show-sdk-path)"
  -target arm64-apple-macosx14.0 -module-cache-path "$benchmark_root/module-cache"
  -O -parse-as-library -swift-version 6 -warn-concurrency -strict-concurrency=complete -warnings-as-errors
)
# Bundle-relative resolution prevents the old subtitle extractor from using a
# host-installed FFmpeg. These CLI bundles are never opened or installed.
for variant in baseline current; do
  app="$run_dir/$variant.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  ln -s "$engine_root" "$app/Contents/Resources/Engine"
  plutil -create xml1 "$app/Contents/Info.plist"
  plutil -insert CFBundleExecutable -string benchmark "$app/Contents/Info.plist"
  plutil -insert CFBundleIdentifier -string "local.airciller.startupbenchmark.$variant" "$app/Contents/Info.plist"
  plutil -insert CFBundlePackageType -string APPL "$app/Contents/Info.plist"
  plutil -insert ACBundledEngineRequired -bool YES "$app/Contents/Info.plist"
done
xcrun swiftc "${common_arguments[@]}" -D STARTUP_BASELINE \
  "${baseline_sources[@]}" "$project_dir/Sources/PlaybackStartupTrace.swift" \
  "$project_dir/Tests/HLSPreparationPerformanceBenchmark.swift" \
  -o "$run_dir/baseline.app/Contents/MacOS/benchmark"
xcrun swiftc "${common_arguments[@]}" \
  "${current_sources[@]}" "$project_dir/Sources/PlaybackStartupTrace.swift" \
  "$project_dir/Sources/PreparedMediaCache.swift" "$project_dir/Sources/HLSPreparationService.swift" \
  "$project_dir/Tests/HLSPreparationPerformanceBenchmark.swift" \
  -o "$run_dir/current.app/Contents/MacOS/benchmark"
baseline="$run_dir/baseline.app/Contents/MacOS/benchmark"
current="$run_dir/current.app/Contents/MacOS/benchmark"
xcrun swiftc --version > "$run_dir/compiler.txt"
sw_vers > "$run_dir/system.txt"
"$ffmpeg" -version > "$run_dir/ffmpeg.txt"
git -C "$project_dir" rev-parse HEAD > "$run_dir/current-revision.txt"
shasum -a 256 "${current_sources[@]}" \
  "$project_dir/Sources/PlaybackStartupTrace.swift" "$project_dir/Sources/PreparedMediaCache.swift" \
  "$project_dir/Sources/HLSPreparationService.swift" "$project_dir/Tests/HLSPreparationPerformanceBenchmark.swift" \
  "$ffmpeg" "$ffprobe" "$fixture_encoder" > "$run_dir/source-and-engine-sha256.txt"
"$current" fixture "$run_dir/fixture" "$ffmpeg" "$fixture_encoder"
modes=(baseline noCache emptyAppCache warmAppCache)
# Rotate mode order each repetition. Warm app-cache fills are separate,
# unmeasured preparations; system file caches are neither purged nor called cold.
for ((repeat_index=0; repeat_index<repetitions; repeat_index++)); do
  for codec in subrip ass; do
    for ((slot=0; slot<4; slot++)); do
      mode_index=$(( (slot + repeat_index) % 4 + 1 ))
      mode="${modes[$mode_index]}"
      executable="$current"
      if [[ "$mode" == baseline ]]; then executable="$baseline"; fi
      "$executable" run "$run_dir/samples/$codec/$mode/$repeat_index" \
        "$run_dir/fixture/fixture.mkv" "$codec" "$mode" "$repeat_index" "$ffmpeg" "$ffprobe"
    done
  done
done
"$current" summarize "$run_dir" "$repetitions" | tee "$run_dir/summary.txt"
echo "Synthetic preparation results and byte-parity evidence: $run_dir"

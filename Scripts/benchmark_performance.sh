#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
source_dir="${1:-$project_dir/Sources}"
benchmark_root="$project_dir/.build/performance"
mkdir -p "$benchmark_root"
run_dir="$(mktemp -d "$benchmark_root/run.XXXXXX")"

# A source directory from an earlier revision can be measured with the same
# fixture and compiler settings. This never builds or installs the app.
xcrun swiftc \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target arm64-apple-macosx14.0 \
  -module-cache-path "$benchmark_root/module-cache" \
  -O -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  -parse-as-library \
  "$source_dir/ASSSubtitleConverter.swift" \
  "$source_dir/ProcessDataBuffer.swift" \
  "$project_dir/Tests/PerformanceBenchmark.swift" \
  -o "$run_dir/benchmark"

"$run_dir/benchmark" "$run_dir/output.vtt" | tee "$run_dir/timings.txt"
echo "Synthetic output and timings: $run_dir"

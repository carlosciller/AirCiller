#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
output_dir="$project_dir/.build/playback-capture-tools"
mkdir -p "$output_dir" "$project_dir/.build/test-module-cache"
arguments=(-parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors
  -target arm64-apple-macosx14.0 -module-cache-path "$project_dir/.build/test-module-cache")
xcrun swiftc "${arguments[@]}" Tests/PlaybackCapture/CapturePolicy.swift \
  Tests/PlaybackCapture/TVSampleCapture.swift -o "$output_dir/capture-samples"
xcrun swiftc "${arguments[@]}" Tests/PlaybackCapture/CapturePolicy.swift \
  Tests/PlaybackCapture/CaptureFrameAnalysis.swift -o "$output_dir/analyze-frames"
echo "Capture tools compiled. No device was opened."

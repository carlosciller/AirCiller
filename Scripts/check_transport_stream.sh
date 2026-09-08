#!/bin/zsh
set -euo pipefail

# Local media only. Does not launch AirCiller, contact a receiver or install anything.
project_dir="${0:A:h:h}"
if [[ $# -ne 2 && ! ( $# -eq 3 && "${3:-}" == "--hdr-hls" ) ]]; then
  echo "Usage: zsh Scripts/check_transport_stream.sh SOURCE NEW_OUTPUT_DIRECTORY [--hdr-hls]" >&2
  exit 2
fi
test_dir="$project_dir/.build/tests"
engine_dir="$project_dir/.build/dependencies/AirCillerEngine-ffmpeg-9.0.1-python-3.13.15/ffmpeg/bin"
mkdir -p "$test_dir" "$project_dir/.build/test-module-cache"
xcrun swiftc -parse-as-library -swift-version 6 -warn-concurrency \
  -strict-concurrency=complete -warnings-as-errors -target arm64-apple-macosx14.0 \
  -module-cache-path "$project_dir/.build/test-module-cache" \
  "$project_dir/Sources/Localization.swift" \
  "$project_dir/Sources/AirCillerError.swift" \
  "$project_dir/Sources/ProcessDataBuffer.swift" \
  "$project_dir/Sources/CancellableProcess.swift" \
  "$project_dir/Sources/CapturedProcess.swift" \
  "$project_dir/Sources/BundledEngine.swift" \
  "$project_dir/Sources/MediaFileTypes.swift" \
  "$project_dir/Sources/MediaModels.swift" \
  "$project_dir/Sources/MediaProbeService.swift" \
  "$project_dir/Sources/ExternalVobSub.swift" \
  "$project_dir/Sources/VODCommandBuilder.swift" \
  "$project_dir/Sources/HDRConfigurationInjector.swift" \
  "$project_dir/Tests/TransportStreamPackagingSmokeTest.swift" \
  -o "$test_dir/transport-stream-packaging"
transport_check_arguments=()
if [[ $# -eq 3 ]]; then transport_check_arguments=("$3"); fi
PYTHONDONTWRITEBYTECODE=1 python3 -c \
  'import sys; sys.path.insert(0, sys.argv[1]); from playback_capture import bounded_command; print(bounded_command(sys.argv[2:], timeout=120).decode(), end="")' \
  "$project_dir/Scripts" "$test_dir/transport-stream-packaging" "$1" "$2" "$engine_dir" "${transport_check_arguments[@]}"
PYTHONDONTWRITEBYTECODE=1 python3 "$project_dir/Scripts/verify_stream_copy.py" "$1" "$2" "$engine_dir"

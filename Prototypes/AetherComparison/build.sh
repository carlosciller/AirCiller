#!/bin/zsh
set -euo pipefail
project="${0:A:h:h:h}"
cd "$project"
engine="$project/.build/dependencies/AetherEngine-7.62.0"
revision=a1d2cab8281cbf06f5f459b05dad4653ad12559f
if [[ ! -d "$engine" ]]; then
  git clone --depth 1 --branch 7.62.0 https://github.com/superuser404notfound/AetherEngine.git "$engine"
fi
[[ "$(git -C "$engine" rev-parse HEAD)" == "$revision" ]] || { echo 'Unexpected Aether revision' >&2; exit 1; }
patch="$project/Prototypes/AetherComparison/engine-target.patch"
if git -C "$engine" apply --check "$patch" 2>/dev/null; then
  git -C "$engine" apply "$patch"
else
  git -C "$engine" apply --reverse --check "$patch"
fi
mkdir -p "$engine/Probes/AirCillerComparison"
cp "$project/Prototypes/AetherComparison/Host.swift" "$engine/Probes/AirCillerComparison/Host.swift"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build \
  --package-path "$engine" --product AirCillerAetherProbe -c release --jobs 4
names=(Localization AirCillerError ProcessDataBuffer CancellableProcess BundledEngine
  MediaModels MediaProbeService ExternalVobSub VODBuildProcess VODCommandBuilder
  StreamDiagnostics SubtitleService ASSSubtitleConverter PGSSubtitleConverter
  SubtitleOCRService SubtitleOCRTextNormalizer AirCillerStorage HDRConfigurationInjector
  HLSAudioTimeline HLSAudioTimelineInfo CapturedProcess PreparedMediaCache
  HLSPreparationService PlaybackStartupTrace)
sources=()
for name in "${names[@]}"; do sources+=("$project/Sources/$name.swift"); done
xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
  -warnings-as-errors -O "${sources[@]}" \
  "$project/Prototypes/AetherComparison/Baseline.swift" -o "$project/.build/aether-comparison-baseline"

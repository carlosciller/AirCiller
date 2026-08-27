#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
output="$project_dir/.build/managed-components/output"
distribution="$project_dir/Distribution"
signer="$project_dir/.build/dependencies/Sparkle-2.9.6/bin/sign_update"
release_tag="${AIRCILLER_COMPONENT_RELEASE_TAG:-v0.10.3}"

ffmpeg_archive="ffmpeg-9.0.1-macos-arm64.zip"
airplay_archive="airplay-python-3.13.15-macos-arm64.zip"
manifest="$distribution/components-v1.json"
signature="$distribution/components-v1.json.sig"

for required in "$output/$ffmpeg_archive" "$output/$airplay_archive" "$signer"; do
  if [[ ! -e "$required" ]]; then
    echo "Missing required file: $required" >&2
    exit 2
  fi
done

mkdir -p "$distribution"

archive_size() {
  stat -f '%z' "$1"
}

archive_sha256() {
  shasum -a 256 "$1" | cut -d ' ' -f 1
}

jq -n \
  --arg release_tag "$release_tag" \
  --arg ffmpeg_archive "$ffmpeg_archive" \
  --arg ffmpeg_sha "$(archive_sha256 "$output/$ffmpeg_archive")" \
  --argjson ffmpeg_size "$(archive_size "$output/$ffmpeg_archive")" \
  --arg airplay_archive "$airplay_archive" \
  --arg airplay_sha "$(archive_sha256 "$output/$airplay_archive")" \
  --argjson airplay_size "$(archive_size "$output/$airplay_archive")" \
  '{
    schemaVersion: 1,
    artifacts: [
      {
        component: "ffmpeg",
        version: "9.0.1+airciller.1",
        architecture: "arm64",
        minimumSystemVersion: "14.0",
        archiveURL: ("https://github.com/carlosciller/AirCiller/releases/download/" + $release_tag + "/" + $ffmpeg_archive),
        archiveSize: $ffmpeg_size,
        sha256: $ffmpeg_sha,
        executablePath: "ffmpeg/bin/ffmpeg"
      },
      {
        component: "airPlay",
        version: "3.13.15+pyatv.0.18.0.1",
        architecture: "arm64",
        minimumSystemVersion: "14.0",
        archiveURL: ("https://github.com/carlosciller/AirCiller/releases/download/" + $release_tag + "/" + $airplay_archive),
        archiveSize: $airplay_size,
        sha256: $airplay_sha,
        executablePath: "airplay/python/bin/python3"
      }
    ]
  }' > "$manifest"

signature_value="$($signer --account AirCiller -p "$manifest")"
if [[ -z "$signature_value" ]]; then
  echo "The component manifest could not be signed." >&2
  exit 3
fi
printf '%s\n' "$signature_value" > "$signature"

echo "$manifest"
echo "$signature"
shasum -a 256 "$output/$ffmpeg_archive" "$output/$airplay_archive"

#!/bin/zsh
set -u

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/AirCiller.app" >&2
  exit 2
fi

app_path="$1"
if [[ ! -d "$app_path" ]]; then
  echo "App not found: $app_path" >&2
  exit 2
fi

failures=0

if codesign --verify --deep --strict "$app_path" 2>/dev/null; then
  echo "Code signature structure: valid"
else
  echo "Code signature structure: failed"
  failures=$((failures + 1))
fi

signature_details="$(codesign -d --verbose=4 "$app_path" 2>&1)"
if [[ "$signature_details" == *"Signature=adhoc"* ]]; then
  echo "Developer ID signature: missing"
  failures=$((failures + 1))
else
  echo "Developer ID signature: present"
fi

if [[ "$signature_details" == *"runtime"* ]]; then
  echo "Hardened Runtime: enabled"
else
  echo "Hardened Runtime: missing"
  failures=$((failures + 1))
fi

if xcrun stapler validate "$app_path" >/dev/null 2>&1; then
  echo "Notarization ticket: valid"
else
  echo "Notarization ticket: missing or invalid"
  failures=$((failures + 1))
fi

if spctl --assess --type execute "$app_path" >/dev/null 2>&1; then
  echo "Gatekeeper assessment: accepted"
else
  echo "Gatekeeper assessment: rejected"
  failures=$((failures + 1))
fi

runtime_marker="$app_path/Contents/Resources/VendorPython/.airciller-python-executable"
if [[ -f "$runtime_marker" ]]; then
  runtime_value="$(<"$runtime_marker")"
  if [[ "$runtime_value" == /* ]]; then
    runtime_path="$runtime_value"
  else
    runtime_path="$app_path/Contents/Resources/$runtime_value"
  fi
  if [[ "$runtime_path" == "$app_path"/* && -x "$runtime_path" ]]; then
    echo "Python runtime: bundled"
  else
    echo "Python runtime: external path ($runtime_path)"
    failures=$((failures + 1))
  fi
else
  echo "Python runtime marker: missing"
  failures=$((failures + 1))
fi

ffmpeg_path="$app_path/Contents/Resources/Engine/ffmpeg/bin/ffmpeg"
ffprobe_path="$app_path/Contents/Resources/Engine/ffmpeg/bin/ffprobe"
if [[ -x "$ffmpeg_path" && -x "$ffprobe_path" ]]; then
  echo "FFmpeg tools: bundled"
else
  echo "FFmpeg tools: missing"
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  echo "Distribution audit: $failures issue(s)"
  exit 1
fi

echo "Distribution audit: ready"

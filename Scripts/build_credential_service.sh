#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
signing_identity="$(/bin/zsh "$project_dir/Scripts/signing_identity.sh")"
if [[ "$signing_identity" == "-" ]]; then
  echo "A configured signing certificate is required for the credential service." >&2
  exit 2
fi
output_root="$project_dir/.local-credential-service"
extra_flags=()
verify_only=false
if [[ "${1:-}" == "--test-fixture" && $# == 1 ]]; then
  output_root="$project_dir/.build/credential-service-fixture"
  extra_flags=(-D AC_CREDENTIAL_FIXTURE)
elif [[ "${1:-}" == "--verify" && $# == 1 ]]; then
  verify_only=true
elif [[ $# != 0 ]]; then
  echo "Usage: zsh Scripts/build_credential_service.sh [--test-fixture|--verify]" >&2
  exit 2
fi
app_path="$output_root/AirCillerCredentialService.xpc"
source_digest="$(shasum -a 256 "$project_dir/CredentialService/main.c" "$project_dir/CredentialService/Info.plist" "${0:A}" | shasum -a 256 | cut -d ' ' -f 1)"
requirement="identifier \"local.carlosciller.AirCiller.CredentialService\" and certificate leaf = H\"$signing_identity\""
if [[ "$verify_only" == true ]]; then
  if [[ ! -f "$output_root/source.sha256" || "$(< "$output_root/source.sha256")" != "$source_digest" ]]; then
    echo "Credential service sources changed or its cache is missing. Prepare and approve a new component explicitly." >&2
    exit 2
  fi
  codesign --verify --strict -R="$requirement" "$app_path"
  echo "$app_path"
  exit 0
fi
if [[ -e "$output_root" ]]; then
  echo "Credential service output already exists. Preserve it; rebuild only with an explicit new output/version." >&2
  exit 2
fi
staging_root="$(mktemp -d "$project_dir/.build/credential-stage-XXXXXX")"
staged_app="$staging_root/AirCillerCredentialService.xpc"
mkdir -p "$staged_app/Contents/MacOS"
cp "$project_dir/CredentialService/Info.plist" "$staged_app/Contents/Info.plist"
xcrun clang -target arm64-apple-macosx14.0 -fblocks -Wall -Wextra -Werror -O2 \
  -D "AC_SIGNER_FINGERPRINT=\"$signing_identity\"" "${extra_flags[@]}" \
  "$project_dir/CredentialService/main.c" -framework Foundation -framework Security \
  -o "$staged_app/Contents/MacOS/AirCillerCredentialService"
codesign --force --options runtime --sign "$signing_identity" "$staged_app"
codesign --verify --strict -R="$requirement" "$staged_app"
printf '%s\n' "$source_digest" > "$staging_root/source.sha256"
mv "$staging_root" "$output_root"
echo "$app_path"

#!/bin/zsh
set -euo pipefail

# A fingerprint is data, never shell configuration. Missing configured keys must
# fail signing; falling back to ad hoc would change the app's Keychain identity.
project_dir="${1:-${0:A:h:h}}"
identity_file="$project_dir/.local-signing-identity"
if (( ${+AIRCILLER_SIGNING_IDENTITY} )); then
  signing_identity="$AIRCILLER_SIGNING_IDENTITY"
elif [[ -e "$identity_file" || -L "$identity_file" ]]; then
  [[ -f "$identity_file" && ! -L "$identity_file" ]] || exit 2
  signing_identity="$(< "$identity_file")"
else
  signing_identity="-"
fi

if [[ "$signing_identity" != "-" && ! "$signing_identity" =~ '^[0-9A-Fa-f]{40}$' ]]; then
  echo "Signing identity must be a certificate SHA-1 fingerprint or '-' for ad hoc signing." >&2
  exit 2
fi
printf '%s\n' "$signing_identity"

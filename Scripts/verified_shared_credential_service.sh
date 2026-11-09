#!/bin/zsh
set -euo pipefail

# Reuse an already approved component across worktrees. Never rebuild or migrate it.
project_dir="${0:A:h:h}"
if [[ $# != 1 || ! -d "$1" ]]; then
  echo "Usage: verified_shared_credential_service.sh approved-project-directory" >&2
  exit 2
fi
approved_project="${1:A}"
for source in CredentialService/main.c CredentialService/Info.plist Scripts/build_credential_service.sh; do
  if ! cmp -s "$project_dir/$source" "$approved_project/$source"; then
    echo "Approved credential component sources differ. Explicit component review is required." >&2
    exit 2
  fi
done
identity="$(/bin/zsh "$project_dir/Scripts/signing_identity.sh" "$approved_project" --require-certificate)"
if [[ "$(/bin/zsh "$project_dir/Scripts/signing_identity.sh" "$project_dir" --require-certificate)" != "$identity" ]]; then
  echo "The app and approved credential component must use the same signing identity." >&2
  exit 2
fi
AIRCILLER_SIGNING_IDENTITY="$identity" /bin/zsh "$approved_project/Scripts/build_credential_service.sh" --verify

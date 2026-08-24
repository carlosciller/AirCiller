#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

scan_paths=(
  Sources
  Tests
  Scripts/airplay_helper.py
  Scripts/make_icon.swift
  README.md
  README.es.md
  CHANGELOG.md
  ARCHITECTURE.md
  CONTRIBUTING.md
  NOTICE.md
  PRIVACY.md
  SECURITY.md
  TESTING.md
  THIRD_PARTY_NOTICES.md
  ROADMAP.md
  LICENSES
)

failed=0

if rg -n '/Users/[^/[:space:]]+/' "${scan_paths[@]}"; then
  echo "Personal filesystem paths were found." >&2
  failed=1
fi

if rg -n '192\.168\.|Monsieur Hulot|YTS\.MX|BYNDR|SARTRE|The Invite|Supergirl|Disclosure Day|The Apartment' "${scan_paths[@]}"; then
  echo "Development media or network data was found." >&2
  failed=1
fi

if rg -n 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AKIA[0-9A-Z]{16}' \
  Sources Tests Scripts/airplay_helper.py Scripts/make_icon.swift; then
  echo "Content resembling secret material was found." >&2
  failed=1
fi

if find Sources Tests Scripts -type f \( -name '*.pyc' -o -name '*.pyo' \) -print -quit | grep -q .; then
  echo "Generated Python bytecode was found." >&2
  failed=1
fi

if [[ -d .git ]]; then
  for generated in .build VendorPython; do
    if ! git check-ignore -q "$generated"; then
      echo "$generated is not protected by .gitignore." >&2
      failed=1
    fi
  done

  if git ls-files | rg '(^|/)(\.build|VendorPython|__pycache__)(/|$)|\.app/|\.(mkv|mp4|m4v|mov|m2ts)$'; then
    echo "Git contains generated artifacts or media files." >&2
    failed=1
  fi
fi

if (( failed != 0 )); then
  exit 1
fi

echo "Public repository content check: OK"

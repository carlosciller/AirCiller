#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

scan_paths=(
  .github
  .gitattributes
  .gitignore
  .swift-format
  Sources
  Tests
  Scripts
  Distribution
  Resources
  Info.plist
  Brewfile
  README.md
  COMPATIBILITY.md
  AGENTS.md
  Docs
  CHANGELOG.md
  ARCHITECTURE.md
  CODE_OF_CONDUCT.md
  CONTRIBUTING.md
  NOTICE.md
  PRIVACY.md
  SECURITY.md
  TESTING.md
  THIRD_PARTY_NOTICES.md
  ROADMAP.md
  DISTRIBUTION.md
  LICENSES
  requirements.in
  requirements.lock
  build.sh
)

public_prose_paths=(
  .github
  Distribution
  README.md
  CHANGELOG.md
  COMPATIBILITY.md
  AGENTS.md
  Docs
  ARCHITECTURE.md
  CODE_OF_CONDUCT.md
  CONTRIBUTING.md
  DISTRIBUTION.md
  NOTICE.md
  PRIVACY.md
  ROADMAP.md
  SECURITY.md
  TESTING.md
  THIRD_PARTY_NOTICES.md
)

failed=0

if grep -RInE --exclude='check_publication.sh' \
  '/Users/[^/[:space:]]+/' "${scan_paths[@]}"; then
  echo "Personal filesystem paths were found." >&2
  failed=1
fi

if grep -RInE --exclude='check_publication.sh' \
  '192\.168\.|Salón|Monsieur Hulot|YTS\.MX|BYNDR|SARTRE|The Invite|Supergirl|Disclosure Day|The Apartment|Airflow|Infuse' \
  "${scan_paths[@]}"; then
  echo "Development media or network data was found." >&2
  failed=1
fi

if grep -RInE \
  '[—–]|made for .+ not|built for .+ not|not just|not only|more than just|rather than' \
  "${public_prose_paths[@]}"; then
  echo "Formulaic public wording or long dashes were found." >&2
  failed=1
fi

if grep -RInE \
  --exclude='check_publication.sh' \
  'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AKIA[0-9A-Z]{16}|github_pat_[A-Za-z0-9_]{20,}|gh[oprsu]_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{20,}' \
  "${scan_paths[@]}"; then
  echo "Content resembling secret material was found." >&2
  failed=1
fi

if find Sources Tests Scripts -type f \( -name '*.pyc' -o -name '*.pyo' \) -print -quit | grep -q .; then
  echo "Generated Python bytecode was found." >&2
  failed=1
fi

if ! jq -e '
  .schemaVersion == 1 and
  (.artifacts | length > 0) and
  all(.artifacts[];
    (.archiveURL | startswith("https://")) and
    (.archiveSize > 0) and
    (.sha256 | test("^[0-9a-fA-F]{64}$")) and
    (.executablePath | test("^(?!/)(?!.*(?:^|/)\\.\\.(?:/|$))[^\\\\]+$"))
  )
' Distribution/components-v1.json >/dev/null; then
  echo "The managed component manifest is malformed or unsafe." >&2
  failed=1
fi

if [[ ! -s Distribution/components-v1.json.sig ]]; then
  echo "The managed component manifest signature is missing." >&2
  failed=1
fi

if [[ -d .git ]]; then
  for generated in .build VendorPython; do
    if ! git check-ignore -q "$generated"; then
      echo "$generated is not protected by .gitignore." >&2
      failed=1
    fi
  done

  if git ls-files | grep -E '(^|/)(\.build|VendorPython|__pycache__)(/|$)|\.app/|\.(zip|mkv|mp4|m4v|mov|m2ts)$'; then
    echo "Git contains generated artifacts or media files." >&2
    failed=1
  fi
fi

if (( failed != 0 )); then
  exit 1
fi

echo "Public repository content check: OK"

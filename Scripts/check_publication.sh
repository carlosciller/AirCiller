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
  echo "Se encontraron rutas personales." >&2
  failed=1
fi

if rg -n '192\.168\.|Monsieur Hulot|YTS\.MX|BYNDR|SARTRE|The Invite|Supergirl|Disclosure Day|The Apartment' "${scan_paths[@]}"; then
  echo "Se encontraron datos de medios o red usados durante el desarrollo." >&2
  failed=1
fi

if rg -n 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AKIA[0-9A-Z]{16}' \
  Sources Tests Scripts/airplay_helper.py Scripts/make_icon.swift; then
  echo "Se encontró material con aspecto de secreto." >&2
  failed=1
fi

if find Sources Tests Scripts -type f \( -name '*.pyc' -o -name '*.pyo' \) -print -quit | grep -q .; then
  echo "Se encontró bytecode Python generado." >&2
  failed=1
fi

if [[ -d .git ]]; then
  for generated in .build VendorPython; do
    if ! git check-ignore -q "$generated"; then
      echo "$generated no está protegido por .gitignore." >&2
      failed=1
    fi
  done

  if git ls-files | rg '(^|/)(\.build|VendorPython|__pycache__)(/|$)|\.app/|\.(mkv|mp4|m4v|mov|m2ts)$'; then
    echo "Git contiene artefactos generados o medios." >&2
    failed=1
  fi
fi

if (( failed != 0 )); then
  exit 1
fi

echo "Contenido preparado para revisión pública: OK"

#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTENSION_DIR="${REPO_ROOT}/Integrations/VSCode"
VSCE="${EXTENSION_DIR}/node_modules/.bin/vsce"
if [[ ! -x "${VSCE}" ]]; then # Fresh clones have no npx cache; require the repository's locked local tool rather than an incidental cached version.
  printf 'Install the packaging tool first: npm ci --ignore-scripts --prefix Integrations/VSCode\n' >&2
  exit 1
fi
VERSION="$(node -p "require('${EXTENSION_DIR}/package.json').version")"
OUTPUT_PATH="${1:-${REPO_ROOT}/build/agentic-mouse-vscode-bridge-${VERSION}.vsix}"
if [[ "${OUTPUT_PATH}" != /* ]]; then
  OUTPUT_PATH="${REPO_ROOT}/${OUTPUT_PATH}"
fi

mkdir -p "$(dirname "${OUTPUT_PATH}")"
(
  cd "${EXTENSION_DIR}"
  "${VSCE}" package --out "${OUTPUT_PATH}"
)
unzip -tq "${OUTPUT_PATH}" >/dev/null
unzip -p "${OUTPUT_PATH}" extension/LICENSE.txt | cmp - "${REPO_ROOT}/LICENSE" # Note: VSCE normalizes the linked project license to LICENSE.txt; verify the published archive carries the exact terms.
printf 'Packaged VS Code bridge %s at %s\n' "${VERSION}" "${OUTPUT_PATH}"

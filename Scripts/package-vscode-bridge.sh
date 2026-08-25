#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTENSION_DIR="${REPO_ROOT}/Integrations/VSCode"
VERSION="$(node -p "require('${EXTENSION_DIR}/package.json').version")"
OUTPUT_PATH="${1:-${REPO_ROOT}/build/agentic-mouse-vscode-bridge-${VERSION}.vsix}"
if [[ "${OUTPUT_PATH}" != /* ]]; then
  OUTPUT_PATH="${REPO_ROOT}/${OUTPUT_PATH}"
fi

mkdir -p "$(dirname "${OUTPUT_PATH}")"
(
  cd "${EXTENSION_DIR}"
  npx --no-install @vscode/vsce package --out "${OUTPUT_PATH}"
)
unzip -tq "${OUTPUT_PATH}" >/dev/null
printf 'Packaged VS Code bridge %s at %s\n' "${VERSION}" "${OUTPUT_PATH}"

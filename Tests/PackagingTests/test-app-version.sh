#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_PLIST="${ROOT}/Resources/Info.plist"
TEMP_DIR="$(mktemp -d /tmp/agentic-mouse-version.XXXXXX)"
TEMP_PLIST="${TEMP_DIR}/Info.plist"
cleanup() {
  /bin/rm -rf -- "${TEMP_DIR}"
}
trap cleanup EXIT

cp "${SOURCE_PLIST}" "${TEMP_PLIST}"
bash "${ROOT}/Scripts/update-app-version.sh" "${TEMP_PLIST}" 9.7.3 42

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${TEMP_PLIST}")" == "9.7.3" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${TEMP_PLIST}")" == "42" ]]
grep -q 'Stable product identity' "${TEMP_PLIST}"

if bash "${ROOT}/Scripts/update-app-version.sh" "${TEMP_PLIST}" 9.7 43 >/dev/null 2>&1; then
  echo "invalid marketing version was accepted" >&2
  exit 1
fi
if bash "${ROOT}/Scripts/update-app-version.sh" "${TEMP_PLIST}" 9.7.3 0 >/dev/null 2>&1; then
  echo "invalid build version was accepted" >&2
  exit 1
fi

CURRENT_MARKETING="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${SOURCE_PLIST}")"
CURRENT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${SOURCE_PLIST}")"
IFS=. read -r CURRENT_MAJOR CURRENT_MINOR CURRENT_PATCH <<< "${CURRENT_MARKETING}"
NEXT_MARKETING="${CURRENT_MAJOR}.${CURRENT_MINOR}.$((10#${CURRENT_PATCH} + 1))"
SOURCE_HASH_BEFORE="$(shasum -a 256 "${SOURCE_PLIST}" | awk '{print $1}')"
[[ "$(bash "${ROOT}/Scripts/package-app.sh" --print-version)" == "v${CURRENT_MARKETING} (${CURRENT_BUILD})" ]]
[[ "$(bash "${ROOT}/Scripts/package-app.sh" --print-next-install-version)" == "v${NEXT_MARKETING} ($((CURRENT_BUILD + 1)))" ]]
[[ "$(RELEASE_VERSION=10.0.0 bash "${ROOT}/Scripts/package-app.sh" --print-next-install-version)" == "v10.0.0 ($((CURRENT_BUILD + 1)))" ]]
if RELEASE_VERSION="${CURRENT_MARKETING}" bash "${ROOT}/Scripts/package-app.sh" --print-next-install-version >/dev/null 2>&1; then
  echo "unchanged marketing version was accepted for a new install" >&2
  exit 1
fi
if RELEASE_VERSION="0.9.9" bash "${ROOT}/Scripts/package-app.sh" --print-next-install-version >/dev/null 2>&1; then
  echo "lower marketing version was accepted for a new install" >&2
  exit 1
fi
SOURCE_HASH_AFTER="$(shasum -a 256 "${SOURCE_PLIST}" | awk '{print $1}')"
[[ "${SOURCE_HASH_BEFORE}" == "${SOURCE_HASH_AFTER}" ]]

echo "app version contract passed"

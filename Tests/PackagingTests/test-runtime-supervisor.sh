#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLIST="${ROOT}/Resources/SupervisorInfo.plist"
MAIN_PLIST="${ROOT}/Resources/Info.plist"
PACKAGE_SCRIPT="${ROOT}/Scripts/package-app.sh"
MAIN_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${MAIN_PLIST}")"
SUPERVISOR_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${PLIST}")"

[[ "${MAIN_IDENTIFIER}" == "com.ethan.agentic-mouse" ]]
[[ "${SUPERVISOR_IDENTIFIER}" == "${MAIN_IDENTIFIER}.runtime-supervisor" ]]
grep -Fq "static let applicationBundleIdentifier = \"${MAIN_IDENTIFIER}\"" \
  "${ROOT}/Sources/AgenticMouseSupervisor/RuntimeSupervisor.swift"
grep -Fq "\"${SUPERVISOR_IDENTIFIER}\"" \
  "${ROOT}/Sources/AgenticMouseApp/LaunchAtLoginController.swift"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${PLIST}")" \
  == "AgenticMouseSupervisor" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "${PLIST}")" == "true" ]]

grep -Fq 'Contents/Library/LoginItems/AgenticMouseSupervisor.app' "${PACKAGE_SCRIPT}"
grep -Fq 'agentic-mouse-supervisor' "${PACKAGE_SCRIPT}"
grep -Fq 'codesign --force --sign "${CODE_SIGN_IDENTITY}" "${SUPERVISOR_APP_DIR}"' \
  "${PACKAGE_SCRIPT}"
grep -Fq '"${SUPERVISOR_APP_DIR}/Contents/Info.plist"' "${PACKAGE_SCRIPT}"
grep -Fq 'SUPERVISOR_MARKETING_VERSION=' "${PACKAGE_SCRIPT}"
grep -Fq 'SUPERVISOR_BUILD_VERSION=' "${PACKAGE_SCRIPT}"
grep -Fq '.executable(name: "agentic-mouse-supervisor"' "${ROOT}/Package.swift" || \
  grep -Fq 'name: "agentic-mouse-supervisor"' "${ROOT}/Package.swift"

echo "runtime supervisor packaging contract passed"

#!/usr/bin/env bash
#
# Builds AgenticMouse.app into ./build/.
#
# Deterministic and self-contained: given the same source tree it produces the
# same bundle layout every time. It does not install anything, does not touch
# ~/Library, does not register its bundled login item, and does not modify any
# system setting. Copying the result out of ./build/ is a separate decision.
#
# The proprietary iCUE SDK is never vendored into this repository. If it is
# available at package time it is copied into the bundle so the app can find it
# without any environment setup; if it is not, the app still builds and simply
# reports lighting as unavailable until the SDK is installed somewhere on its
# search path.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build"
APP_NAME="AgenticMouse"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
SUPERVISOR_APP_DIR="${APP_DIR}/Contents/Library/LoginItems/AgenticMouseSupervisor.app"
CONFIGURATION="${CONFIGURATION:-release}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
INSTALL_CANDIDATE="${INSTALL_CANDIDATE:-0}"
INFO_PLIST="${REPO_ROOT}/Resources/Info.plist"
CURRENT_MARKETING_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
CURRENT_BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
REQUESTED_RELEASE_VERSION="${RELEASE_VERSION:-}"

if [[ ! "${CURRENT_MARKETING_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || [[ ! "${CURRENT_BUILD_VERSION}" =~ ^[1-9][0-9]*$ ]]; then
  printf '\033[31m error:\033[0m invalid app version metadata in %s.\n' "${INFO_PLIST}" >&2
  exit 65
fi

version_is_greater() {
  local candidate="$1"
  local current="$2"
  local candidate_major candidate_minor candidate_patch
  local current_major current_minor current_patch
  IFS=. read -r candidate_major candidate_minor candidate_patch <<< "${candidate}"
  IFS=. read -r current_major current_minor current_patch <<< "${current}"
  local candidate_parts=("${candidate_major}" "${candidate_minor}" "${candidate_patch}")
  local current_parts=("${current_major}" "${current_minor}" "${current_patch}")
  local index
  for index in 0 1 2; do
    if (( 10#${candidate_parts[$index]} > 10#${current_parts[$index]} )); then
      return 0
    fi
    if (( 10#${candidate_parts[$index]} < 10#${current_parts[$index]} )); then
      return 1
    fi
  done
  return 1
}

IFS=. read -r CURRENT_MAJOR CURRENT_MINOR CURRENT_PATCH <<< "${CURRENT_MARKETING_VERSION}"
DEFAULT_NEXT_MARKETING_VERSION="${CURRENT_MAJOR}.${CURRENT_MINOR}.$((10#${CURRENT_PATCH} + 1))"
NEXT_INSTALL_MARKETING_VERSION="${REQUESTED_RELEASE_VERSION:-${DEFAULT_NEXT_MARKETING_VERSION}}"

if [[ ! "${NEXT_INSTALL_MARKETING_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf '\033[31m error:\033[0m release version must use numeric major.minor.patch.\n' >&2
  exit 65
fi
if ! version_is_greater "${NEXT_INSTALL_MARKETING_VERSION}" "${CURRENT_MARKETING_VERSION}"; then
  printf '\033[31m error:\033[0m the next install version %s must be greater than the recorded version %s.\n' \
    "${NEXT_INSTALL_MARKETING_VERSION}" "${CURRENT_MARKETING_VERSION}" >&2
  exit 65
fi

PACKAGE_MARKETING_VERSION="${CURRENT_MARKETING_VERSION}"
PACKAGE_BUILD_VERSION="${CURRENT_BUILD_VERSION}"
if [[ "${INSTALL_CANDIDATE}" == "1" ]]; then
  PACKAGE_MARKETING_VERSION="${NEXT_INSTALL_MARKETING_VERSION}"
  PACKAGE_BUILD_VERSION="$((CURRENT_BUILD_VERSION + 1))"
fi
PACKAGE_VERSION_LABEL="v${PACKAGE_MARKETING_VERSION} (${PACKAGE_BUILD_VERSION})"

case "${1:-}" in
  --print-version)
    printf 'v%s (%s)\n' "${CURRENT_MARKETING_VERSION}" "${CURRENT_BUILD_VERSION}"
    exit 0
    ;;
  --print-next-install-version)
    printf 'v%s (%s)\n' "${NEXT_INSTALL_MARKETING_VERSION}" "$((CURRENT_BUILD_VERSION + 1))"
    exit 0
    ;;
  "") ;;
  *)
    printf 'usage: %s [--print-version|--print-next-install-version]\n' "$0" >&2
    exit 64
    ;;
esac

if [[ "${INSTALL_CANDIDATE}" == "1" && "${CODE_SIGN_IDENTITY}" == "-" ]]; then
  printf '\033[31m error:\033[0m INSTALL_CANDIDATE=1 requires a stable Developer ID identity; refusing an ad-hoc bundle that would invalidate Accessibility trust.\n' >&2
  exit 1
fi

# Where to look for the SDK to embed. Override with ICUE_SDK_FRAMEWORK.
ICUE_SDK_FRAMEWORK="${ICUE_SDK_FRAMEWORK:-/Volumes/iCUESDK/iCUESDK.framework}"

log() { printf '\033[1m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[33m warning:\033[0m %s\n' "$1" >&2; }

log "Building (${CONFIGURATION})"
swift build --package-path "${REPO_ROOT}" -c "${CONFIGURATION}"

BIN_PATH="$(swift build --package-path "${REPO_ROOT}" -c "${CONFIGURATION}" --show-bin-path)"

log "Assembling ${APP_NAME}.app ${PACKAGE_VERSION_LABEL}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
mkdir -p "${APP_DIR}/Contents/Frameworks"
mkdir -p "${SUPERVISOR_APP_DIR}/Contents/MacOS"

cp "${BIN_PATH}/agentic-mouse" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "${BIN_PATH}/agentic-mouse-doctor" "${APP_DIR}/Contents/MacOS/agentic-mouse-doctor"
cp "${BIN_PATH}/agentic-mouse-supervisor" \
  "${SUPERVISOR_APP_DIR}/Contents/MacOS/AgenticMouseSupervisor"
cp "${INFO_PLIST}" "${APP_DIR}/Contents/Info.plist"
cp "${REPO_ROOT}/Resources/SupervisorInfo.plist" \
  "${SUPERVISOR_APP_DIR}/Contents/Info.plist"
bash "${REPO_ROOT}/Scripts/package-vscode-bridge.sh" \
  "${APP_DIR}/Contents/Resources/AgenticMouseVSCodeBridge.vsix"
bash "${REPO_ROOT}/Scripts/update-app-version.sh" \
  "${APP_DIR}/Contents/Info.plist" \
  "${PACKAGE_MARKETING_VERSION}" \
  "${PACKAGE_BUILD_VERSION}"
bash "${REPO_ROOT}/Scripts/update-app-version.sh" \
  "${SUPERVISOR_APP_DIR}/Contents/Info.plist" \
  "${PACKAGE_MARKETING_VERSION}" \
  "${PACKAGE_BUILD_VERSION}"
SUPERVISOR_MARKETING_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${SUPERVISOR_APP_DIR}/Contents/Info.plist")"
SUPERVISOR_BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${SUPERVISOR_APP_DIR}/Contents/Info.plist")"
if [[ "${SUPERVISOR_MARKETING_VERSION}" != "${PACKAGE_MARKETING_VERSION}" \
  || "${SUPERVISOR_BUILD_VERSION}" != "${PACKAGE_BUILD_VERSION}" ]]; then
  printf '\033[31m error:\033[0m runtime supervisor version does not match the outer app.\n' >&2
  exit 1
fi

# The app dlopen()s the SDK from Contents/Frameworks first, so no rpath or
# install_name surgery is needed.
if [[ -d "${ICUE_SDK_FRAMEWORK}" ]]; then
  log "Embedding iCUE SDK from ${ICUE_SDK_FRAMEWORK}"
  cp -R "${ICUE_SDK_FRAMEWORK}" "${APP_DIR}/Contents/Frameworks/"
else
  warn "iCUE SDK not found at ${ICUE_SDK_FRAMEWORK}."
  if [[ "${CODE_SIGN_IDENTITY}" != "-" ]]; then
    printf '\033[31m error:\033[0m a Developer-ID build requires the audited iCUE SDK; refusing to produce a crippled install candidate.\n' >&2
    exit 1
  fi
  warn "The app will still run; lighting and multi-tap stay unavailable until"
  warn "the SDK is installed. See docs/SETUP.md. Set ICUE_SDK_FRAMEWORK to"
  warn "point at iCUESDK.framework and re-run to embed it."
fi

# The portable default remains ad-hoc, but a real identity can be supplied for
# a stable designated requirement. That lets macOS retain Accessibility
# approval across rebuilt bundles installed at the same path.
if [[ "${CODE_SIGN_IDENTITY}" == "-" ]]; then
  log "Signing (ad-hoc)"
else
  log "Signing (${CODE_SIGN_IDENTITY})"
fi
if ! codesign --force --sign "${CODE_SIGN_IDENTITY}" \
  "${APP_DIR}/Contents/MacOS/agentic-mouse-doctor"; then
  printf '\033[31m error:\033[0m codesign failed for the bundled doctor; refusing to continue.\n' >&2
  exit 1
fi
if ! codesign --force --sign "${CODE_SIGN_IDENTITY}" "${SUPERVISOR_APP_DIR}"; then
  printf '\033[31m error:\033[0m codesign failed for the runtime supervisor; refusing to continue.\n' >&2
  exit 1
fi

# Sign the app bundle without --deep. The embedded iCUE framework is an
# independently signed vendor binary; --deep would rewrite that audited binary
# even though its existing nested signature is already valid.
if ! codesign --force --sign "${CODE_SIGN_IDENTITY}" "${APP_DIR}"; then
  printf '\033[31m error:\033[0m codesign failed for %s; refusing to produce an installable app.\n' \
    "${CODE_SIGN_IDENTITY}" >&2
  exit 1
fi

if ! codesign --verify --deep --strict "${APP_DIR}"; then
  printf '\033[31m error:\033[0m signature verification failed; refusing to continue.\n' >&2
  exit 1
fi

if [[ "${INSTALL_CANDIDATE}" == "1" ]]; then
  # Record the exact successfully signed candidate only after all packaging and
  # signature gates pass. A failed candidate never consumes either version.
  LATEST_MARKETING_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
  LATEST_BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
  if [[ "${LATEST_MARKETING_VERSION}" != "${CURRENT_MARKETING_VERSION}" \
    || "${LATEST_BUILD_VERSION}" != "${CURRENT_BUILD_VERSION}" ]]; then
    printf '\033[31m error:\033[0m source version changed during packaging; refusing to advance it or approve this candidate.\n' >&2
    exit 75
  fi
  bash "${REPO_ROOT}/Scripts/update-app-version.sh" \
    "${INFO_PLIST}" \
    "${PACKAGE_MARKETING_VERSION}" \
    "${PACKAGE_BUILD_VERSION}"
  log "Recorded signed candidate ${PACKAGE_VERSION_LABEL}"
fi

log "Done: ${APP_DIR} (${PACKAGE_VERSION_LABEL})"
if [[ "${CODE_SIGN_IDENTITY}" == "-" ]]; then
  cat <<EOF

Ad-hoc development bundle only. Do not move this build to /Applications: its
identity is not stable enough for Accessibility permission. Use the documented
Developer-ID install-candidate command in docs/SETUP.md instead.
EOF
  exit 0
fi
cat <<EOF

Next steps (all manual, none of them performed by this script):

  1. Preserve the current installed app as rollback, then install this signed candidate.
  2. Launch it once. It appears in the menu bar; it has no Dock icon.
  3. Grant Accessibility permission when asked, then quit and relaunch.
  4. Copy Config/config.example.json to ~/.config/agentic-mouse/config.json,
     fill in the REPLACE_ME values, and chmod 600 it.
  5. Verify with:  ${APP_DIR}/Contents/MacOS/agentic-mouse-doctor config
                   ${APP_DIR}/Contents/MacOS/agentic-mouse-doctor icue
EOF

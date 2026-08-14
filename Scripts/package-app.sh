#!/usr/bin/env bash
#
# Builds AgenticMouse.app into ./build/.
#
# Deterministic and self-contained: given the same source tree it produces the
# same bundle layout every time. It does not install anything, does not touch
# ~/Library, does not register a LaunchAgent, and does not modify any system
# setting. Copying the result out of ./build/ is a separate, manual decision.
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
CONFIGURATION="${CONFIGURATION:-release}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
INSTALL_CANDIDATE="${INSTALL_CANDIDATE:-0}"

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

log "Assembling ${APP_NAME}.app"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
mkdir -p "${APP_DIR}/Contents/Frameworks"

cp "${BIN_PATH}/agentic-mouse" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "${BIN_PATH}/agentic-mouse-doctor" "${APP_DIR}/Contents/MacOS/agentic-mouse-doctor"
cp "${REPO_ROOT}/Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"

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

log "Done: ${APP_DIR}"
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

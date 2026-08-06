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
  warn "The app will still run; lighting and multi-tap stay unavailable until"
  warn "the SDK is installed. See docs/SETUP.md. Set ICUE_SDK_FRAMEWORK to"
  warn "point at iCUESDK.framework and re-run to embed it."
fi

# Ad-hoc signature for a locally built bundle. This is not a stable signing
# identity: macOS may invalidate Accessibility approval after any rebuild even
# when the bundle id and installation path remain unchanged.
log "Signing (ad-hoc)"
codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || \
  warn "codesign failed; the app will still run but must be checked again in Accessibility settings."

log "Done: ${APP_DIR}"
cat <<EOF

Next steps (all manual, none of them performed by this script):

  1. Move ${APP_NAME}.app wherever you want it, e.g. /Applications.
  2. Launch it once. It appears in the menu bar; it has no Dock icon.
  3. Grant Accessibility permission when asked, then quit and relaunch.
  4. Copy Config/config.example.json to ~/.config/agentic-mouse/config.json,
     fill in the REPLACE_ME values, and chmod 600 it.
  5. Verify with:  ${APP_DIR}/Contents/MacOS/agentic-mouse-doctor config
                   ${APP_DIR}/Contents/MacOS/agentic-mouse-doctor icue
EOF

#!/usr/bin/env bash
# Sign only the exact trusted CI build, then use the canonical notarization gate.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
: "${AGENTIC_MOUSE_BUILD_DIR:?Set a task-owned build directory}"
: "${CODE_SIGN_IDENTITY:?Set the stable Developer ID identity}"
INPUT=${1:?Pass the downloaded CI artifact directory}
python3 - "$ROOT" "$INPUT" <<'PY'
import hashlib,json,pathlib,subprocess,sys
root,source=map(pathlib.Path,sys.argv[1:])
receipt=json.loads((source/'build-receipt.json').read_text())
assert receipt['commit']==subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
assert receipt['sha256']==hashlib.sha256((source/'AgenticMouse-prebuilt.zip').read_bytes()).hexdigest()
PY
test ! -e "$AGENTIC_MOUSE_BUILD_DIR/AgenticMouse.app"
mkdir -p "$AGENTIC_MOUSE_BUILD_DIR"
ditto -xk "$INPUT/AgenticMouse-prebuilt.zip" "$AGENTIC_MOUSE_BUILD_DIR"
APP="$AGENTIC_MOUSE_BUILD_DIR/AgenticMouse.app"
for key in CFBundleVersion CFBundleShortVersionString CFBundleIdentifier SUPublicEDKey; do
  [[ "$(/usr/libexec/PlistBuddy -c "Print $key" "$ROOT/Resources/Info.plist")" == "$(/usr/libexec/PlistBuddy -c "Print $key" "$APP/Contents/Info.plist")" ]]
done
test ! -e "$APP/Contents/Frameworks/iCUESDK.framework"
for component in "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" \
  "$APP/Contents/Frameworks/Sparkle.framework" \
  "$APP/Contents/MacOS/agentic-mouse-doctor" \
  "$APP/Contents/Library/LoginItems/AgenticMouseSupervisor.app"; do
  codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$component"
done
codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" \
  --entitlements "$ROOT/Resources/Distribution.entitlements" "$APP"
bash "$ROOT/Scripts/notarize-release.sh"

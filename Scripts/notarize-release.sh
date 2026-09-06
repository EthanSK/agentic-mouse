#!/usr/bin/env bash
# Run only against a clean, checked public-source distribution build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/AgenticMouse.app"
OUT="$ROOT/build/release"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an existing notarytool Keychain profile}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD" =~ ^[1-9][0-9]*$ ]]
test ! -e "$APP/Contents/Frameworks/iCUESDK.framework"
codesign --verify --deep --strict "$APP"
for executable in "$APP/Contents/MacOS/AgenticMouse" "$APP/Contents/MacOS/agentic-mouse-doctor" "$APP/Contents/Library/LoginItems/AgenticMouseSupervisor.app/Contents/MacOS/AgenticMouseSupervisor"; do
  details=$(codesign -dvv "$executable" 2>&1)
  [[ "$details" == *"Authority=Developer ID Application:"* && "$details" == *"runtime"* && "$details" == *"Timestamp="* ]]
  lipo "$executable" -verify_arch arm64 x86_64
done
mkdir -p "$OUT"
SUBMISSION="$ROOT/build/notary-submission.zip"
ditto -c -k --keepParent "$APP" "$SUBMISSION"
NOTARY_FLAGS=()
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then NOTARY_FLAGS=(--keychain "$NOTARY_KEYCHAIN"); fi
xcrun notarytool submit "$SUBMISSION" --keychain-profile "$NOTARY_PROFILE" ${NOTARY_FLAGS[@]+"${NOTARY_FLAGS[@]}"} --wait --timeout 30m --output-format json > "$OUT/notarization.json"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"] == "Accepted", "Apple did not accept this build"' "$OUT/notarization.json"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict "$APP"
spctl --assess --type execute --verbose=2 "$APP"
ARCHIVE="AgenticMouse-${VERSION}-build.${BUILD}-universal.zip"
ditto -c -k --keepParent "$APP" "$OUT/$ARCHIVE"
# Verify the actual final archive, including its stapled ticket.
VERIFY=$(mktemp -d)
trap 'rm -rf "$VERIFY"' EXIT
ditto -x -k "$OUT/$ARCHIVE" "$VERIFY"
codesign --verify --deep --strict "$VERIFY/AgenticMouse.app"
xcrun stapler validate "$VERIFY/AgenticMouse.app"
spctl --assess --type execute --verbose=2 "$VERIFY/AgenticMouse.app"
(cd "$OUT" && shasum -a 256 "$ARCHIVE" > SHA256SUMS)
python3 - "$ROOT" "$VERSION" "$BUILD" "$ARCHIVE" <<'PY'
import hashlib,json,pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1]); version,build,archive=sys.argv[2:]
path=root/'build/release'/archive
manifest=dict(version=version,build=int(build),commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),archive=archive,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),architectures=['arm64','x86_64'],minimumMacOS='13.0',notarized=True,stapled=True,bundledCorsairSDK=False)
(path.parent/'release.json').write_text(json.dumps(manifest,indent=2)+'\n')
PY

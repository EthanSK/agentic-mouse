#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  echo "usage: update-app-version.sh INFO_PLIST MARKETING_VERSION BUILD_VERSION" >&2
  exit 64
fi

INFO_PLIST="$1"
MARKETING_VERSION="$2"
BUILD_VERSION="$3"

if [[ ! -f "${INFO_PLIST}" ]]; then
  echo "error: Info.plist not found: ${INFO_PLIST}" >&2
  exit 66
fi
if [[ ! "${MARKETING_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: marketing version must use numeric major.minor.patch" >&2
  exit 65
fi
if [[ ! "${BUILD_VERSION}" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: build version must be a positive integer" >&2
  exit 65
fi

TEMP_PLIST="${INFO_PLIST}.version.$$"
cleanup() {
  if [[ -e "${TEMP_PLIST}" ]]; then
    /bin/rm -f -- "${TEMP_PLIST}"
  fi
}
trap cleanup EXIT

awk -v marketing="${MARKETING_VERSION}" -v build="${BUILD_VERSION}" '
  /<key>CFBundleShortVersionString<\/key>/ {
    waiting_for = "marketing"
    print
    next
  }
  /<key>CFBundleVersion<\/key>/ {
    waiting_for = "build"
    print
    next
  }
  waiting_for == "marketing" && /<string>[^<]*<\/string>/ {
    sub(/<string>[^<]*<\/string>/, "<string>" marketing "</string>")
    marketing_count += 1
    waiting_for = ""
    print
    next
  }
  waiting_for == "build" && /<string>[^<]*<\/string>/ {
    sub(/<string>[^<]*<\/string>/, "<string>" build "</string>")
    build_count += 1
    waiting_for = ""
    print
    next
  }
  { print }
  END {
    if (marketing_count != 1 || build_count != 1) {
      exit 42
    }
  }
' "${INFO_PLIST}" > "${TEMP_PLIST}"

plutil -lint "${TEMP_PLIST}" >/dev/null
/bin/mv -f -- "${TEMP_PLIST}" "${INFO_PLIST}"

ACTUAL_MARKETING="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
ACTUAL_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
if [[ "${ACTUAL_MARKETING}" != "${MARKETING_VERSION}" || "${ACTUAL_BUILD}" != "${BUILD_VERSION}" ]]; then
  echo "error: version verification failed after updating ${INFO_PLIST}" >&2
  exit 74
fi

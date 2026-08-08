#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /path/to/BatteryHarbor-*.dmg" >&2
    exit 2
fi
DMG_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
test -f "$DMG_PATH"

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/battery-harbor-verify.XXXXXX")"
MOUNT_POINT="$TEMP_ROOT/mount"
mkdir -p "$MOUNT_POINT"
MOUNTED=0

cleanup() {
    if [[ "$MOUNTED" -eq 1 ]]; then
        hdiutil detach "$MOUNT_POINT" -quiet || true
    fi
    rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

hdiutil verify "$DMG_PATH"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$DMG_PATH" >/dev/null
MOUNTED=1

APP_PATH="$MOUNT_POINT/Battery Harbor.app"
HELPER_PATH="$APP_PATH/Contents/Library/HelperTools/BatteryHarborHelper"
test -d "$APP_PATH"
test -x "$HELPER_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

APP_IDENTIFIER="$(codesign -dv --verbose=2 "$APP_PATH" 2>&1 | sed -n 's/^Identifier=//p')"
HELPER_IDENTIFIER="$(codesign -dv --verbose=2 "$HELPER_PATH" 2>&1 | sed -n 's/^Identifier=//p')"
test "$APP_IDENTIFIER" = "io.github.muu3327.batteryharbor"
test "$HELPER_IDENTIFIER" = "io.github.muu3327.batteryharbor.helper"

APP_CERT_PREFIX="$TEMP_ROOT/app-cert-"
HELPER_CERT_PREFIX="$TEMP_ROOT/helper-cert-"
codesign -d --extract-certificates="$APP_CERT_PREFIX" "$APP_PATH"
codesign -d --extract-certificates="$HELPER_CERT_PREFIX" "$HELPER_PATH"
APP_CERT_SHA256="$(shasum -a 256 "${APP_CERT_PREFIX}0" | awk '{print $1}')"
HELPER_CERT_SHA256="$(shasum -a 256 "${HELPER_CERT_PREFIX}0" | awk '{print $1}')"
test "$APP_CERT_SHA256" = "$HELPER_CERT_SHA256"

echo "DMG structure and nested signatures are valid."
echo "App identifier: $APP_IDENTIFIER"
echo "Helper identifier: $HELPER_IDENTIFIER"
echo "Shared leaf certificate SHA-256: $APP_CERT_SHA256"

if spctl --assess --type execute "$APP_PATH" >/dev/null 2>&1; then
    echo "Warning: Gatekeeper unexpectedly accepted this unnotarized community build."
else
    echo "Gatekeeper rejection is expected for an unnotarized self-signed build."
fi

#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_LABEL="${1:-0.1.0-alpha.2}"
SIGNING_IDENTITY="${BATTERY_HARBOR_SIGNING_IDENTITY:-Battery Harbor Open Source Release}"
OUTPUT_DIR="$PROJECT_ROOT/.build/releases"
OUTPUT_BASENAME="BatteryHarbor-${RELEASE_LABEL}-macos-arm64-unnotarized"
DMG_PATH="$OUTPUT_DIR/$OUTPUT_BASENAME.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
MANIFEST_PATH="$OUTPUT_DIR/$OUTPUT_BASENAME.txt"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/battery-harbor-release.XXXXXX")"

cleanup() {
    rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

if [[ -e "$DMG_PATH" || -e "$CHECKSUM_PATH" || -e "$MANIFEST_PATH" ]]; then
    echo "Release output already exists: $OUTPUT_BASENAME" >&2
    echo "Move the existing files out of $OUTPUT_DIR before rebuilding." >&2
    exit 1
fi

if ! security find-certificate -c "$SIGNING_IDENTITY" -p >/dev/null 2>&1; then
    echo "Code-signing certificate was not found: $SIGNING_IDENTITY" >&2
    echo "Create the community release certificate before running this script." >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Running unit tests..."
(cd "$PROJECT_ROOT" && swift test)

echo "Building unsigned arm64 Release app..."
xcodebuild \
    -project "$PROJECT_ROOT/BatteryHarbor.xcodeproj" \
    -scheme BatteryHarbor \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$TEMP_ROOT/DerivedData" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build

BUILT_APP="$TEMP_ROOT/DerivedData/Build/Products/Release/BatteryHarbor.app"
SIGNED_APP="$TEMP_ROOT/Battery Harbor.app"
HELPER_PATH="$SIGNED_APP/Contents/Library/HelperTools/BatteryHarborHelper"

test -d "$BUILT_APP"
ditto "$BUILT_APP" "$SIGNED_APP"
test -x "$HELPER_PATH"

echo "Signing root Helper and App with: $SIGNING_IDENTITY"
codesign --force --options runtime --timestamp=none --sign "$SIGNING_IDENTITY" "$HELPER_PATH"
codesign --force --options runtime --timestamp=none --sign "$SIGNING_IDENTITY" "$SIGNED_APP"
codesign --verify --deep --strict --verbose=2 "$SIGNED_APP"

APP_IDENTIFIER="$(codesign -dv --verbose=2 "$SIGNED_APP" 2>&1 | sed -n 's/^Identifier=//p')"
HELPER_IDENTIFIER="$(codesign -dv --verbose=2 "$HELPER_PATH" 2>&1 | sed -n 's/^Identifier=//p')"
test "$APP_IDENTIFIER" = "io.github.muu3327.batteryharbor"
test "$HELPER_IDENTIFIER" = "io.github.muu3327.batteryharbor.helper"

APP_CERT_PREFIX="$TEMP_ROOT/app-cert-"
HELPER_CERT_PREFIX="$TEMP_ROOT/helper-cert-"
codesign -d --extract-certificates="$APP_CERT_PREFIX" "$SIGNED_APP"
codesign -d --extract-certificates="$HELPER_CERT_PREFIX" "$HELPER_PATH"
APP_CERT_SHA256="$(shasum -a 256 "${APP_CERT_PREFIX}0" | awk '{print $1}')"
HELPER_CERT_SHA256="$(shasum -a 256 "${HELPER_CERT_PREFIX}0" | awk '{print $1}')"
test "$APP_CERT_SHA256" = "$HELPER_CERT_SHA256"

STAGING_DIR="$TEMP_ROOT/DMG"
mkdir -p "$STAGING_DIR"
ditto "$SIGNED_APP" "$STAGING_DIR/Battery Harbor.app"
ln -s /Applications "$STAGING_DIR/Applications"

cat > "$STAGING_DIR/安装前必读.txt" <<'EOF'
电池港社区测试版未经 Apple 公证。

1. 将“Battery Harbor.app”拖入 Applications。
2. 首次打开被阻止后，前往“系统设置 → 隐私与安全性 → 仍要打开”。
3. 在电池港“设置 → 充电”中注册控制模块，并在登录项设置中批准。
4. 必须完成内置写入、回读和原值恢复安全自检后，才可启用充电控制。

请只从项目官方 GitHub Releases 下载，并核对 SHA-256。
不要关闭 Gatekeeper 或 SIP，不要跳过安全自检。
EOF

echo "Creating unnotarized DMG..."
hdiutil create \
    -volname "Battery Harbor $RELEASE_LABEL" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    "$DMG_PATH"

shasum -a 256 "$DMG_PATH" > "$CHECKSUM_PATH"
cat > "$MANIFEST_PATH" <<EOF
Release: $RELEASE_LABEL
Architecture: arm64
Bundle ID: $APP_IDENTIFIER
Helper ID: $HELPER_IDENTIFIER
Signing identity: $SIGNING_IDENTITY
Leaf certificate SHA-256: $APP_CERT_SHA256
Apple notarization: no
DMG: $(basename "$DMG_PATH")
DMG SHA-256: $(awk '{print $1}' "$CHECKSUM_PATH")
EOF

echo "Community release created:"
echo "  $DMG_PATH"
echo "  $CHECKSUM_PATH"
echo "  $MANIFEST_PATH"

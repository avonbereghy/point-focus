#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="PointFocus"
APP_BUNDLE="build/${APP_NAME}.app"
INSTALL_DIR="${HOME}/Applications"

echo "==> Building universal release binary"
swift build -c release --arch arm64 --arch x86_64

BIN_PATH=".build/apple/Products/Release/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
    echo "error: built binary not found at ${BIN_PATH}"
    exit 1
fi

echo "==> Assembling ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

echo "==> Ad-hoc signing"
codesign --force --sign - \
    --entitlements Resources/PointFocus.entitlements \
    --timestamp=none \
    "${APP_BUNDLE}"

echo "==> Installing to ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
cp -R "${APP_BUNDLE}" "${INSTALL_DIR}/"

echo "==> Installed to ${INSTALL_DIR}/${APP_NAME}.app"

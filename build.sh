#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="PointFocus"
BUNDLE_ID="com.avb.pointfocus"
CERT_NAME="PointFocus Local Sign"
APP_BUNDLE="build/${APP_NAME}.app"
INSTALL_DIR="${HOME}/Applications"

# ---------- Step 0: ensure a stable local code-signing identity ----------
#
# Ad-hoc signing (--sign -) produces a fresh CDHash on every build, which
# orphans TCC grants (Accessibility, Input Monitoring) every time. Signing
# with a stable self-signed cert keeps the Designated Requirement constant,
# so TCC recognises rebuilds as the same app and grants persist.
#
# This block creates the cert on first run; subsequent builds reuse it.
# To reset: `security delete-identity -c "${CERT_NAME}" ~/Library/Keychains/login.keychain-db`

if ! security find-identity -v -p codesigning | grep -q "\"${CERT_NAME}\""; then
    echo "==> Creating local code-signing certificate '${CERT_NAME}'"
    WORK=$(mktemp -d)
    trap "rm -rf '$WORK'" EXIT

    openssl genrsa -out "$WORK/key.pem" 2048 2>/dev/null
    openssl req -x509 -new -key "$WORK/key.pem" -out "$WORK/cert.pem" -days 3650 \
        -subj "/CN=${CERT_NAME}" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning" \
        -addext "basicConstraints=critical,CA:false" 2>/dev/null

    # macOS `security` uses the older PKCS12 format; force legacy ciphers + a
    # non-empty passphrase so SecKeychainItemImport's MAC check succeeds.
    P12_PASS="pointfocus"
    openssl pkcs12 -export \
        -in "$WORK/cert.pem" -inkey "$WORK/key.pem" \
        -out "$WORK/cert.p12" \
        -passout "pass:${P12_PASS}" \
        -name "${CERT_NAME}" \
        -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg SHA1

    security import "$WORK/cert.p12" \
        -k "${HOME}/Library/Keychains/login.keychain-db" \
        -P "${P12_PASS}" \
        -T /usr/bin/codesign

    # Self-signed certs are not visible to the codesigning policy unless they
    # carry explicit user-domain trust for code signing. This call prompts
    # for the login keychain password once.
    security add-trusted-cert \
        -r trustRoot \
        -p codeSign \
        -k "${HOME}/Library/Keychains/login.keychain-db" \
        "$WORK/cert.pem"

    if ! security find-identity -v -p codesigning | grep -q "\"${CERT_NAME}\""; then
        echo "error: certificate was imported but is not visible to codesign."
        echo "       Open Keychain Access > login > Certificates, find '${CERT_NAME}',"
        echo "       double-click it, expand Trust, and set 'Code Signing' to Always Trust."
        exit 1
    fi
    echo "==> Certificate '${CERT_NAME}' ready in login keychain."
    echo "    (TCC grants from this point forward will persist across rebuilds.)"
fi

# ---------- Step 1: build universal release binary ----------
echo "==> Building universal release binary"
swift build -c release --arch arm64 --arch x86_64

BIN_PATH=".build/apple/Products/Release/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
    echo "error: built binary not found at ${BIN_PATH}"
    exit 1
fi

# ---------- Step 2: assemble app bundle ----------
echo "==> Assembling ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# ---------- Step 3: sign with the stable cert ----------
echo "==> Signing with ${CERT_NAME}"
codesign --force --sign "${CERT_NAME}" \
    --entitlements Resources/PointFocus.entitlements \
    --identifier "${BUNDLE_ID}" \
    --timestamp=none \
    "${APP_BUNDLE}"

# ---------- Step 4: install ----------
echo "==> Installing to ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
cp -R "${APP_BUNDLE}" "${INSTALL_DIR}/"

echo "==> Installed to ${INSTALL_DIR}/${APP_NAME}.app"

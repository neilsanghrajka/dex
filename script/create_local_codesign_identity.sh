#!/usr/bin/env bash
set -euo pipefail

IDENTITY="${DEX_CODESIGN_IDENTITY:-Dex Local Development}"
KEYCHAIN="${DEX_CODESIGN_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
P12_PASSWORD="${DEX_CODESIGN_P12_PASSWORD:-dex-local-development}"

if /usr/bin/security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | /usr/bin/grep -F "\"$IDENTITY\"" >/dev/null; then
  echo "Code signing identity already exists: $IDENTITY"
  exit 0
fi

TMP_DIR="$(/usr/bin/mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

OPENSSL_CONFIG="$TMP_DIR/codesign.cnf"
KEY_PATH="$TMP_DIR/codesign.key"
CERT_PATH="$TMP_DIR/codesign.crt"
P12_PATH="$TMP_DIR/codesign.p12"

cat >"$OPENSSL_CONFIG" <<CONFIG
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = codesign_extensions
prompt = no

[ req_distinguished_name ]
CN = $IDENTITY

[ codesign_extensions ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
CONFIG

/usr/bin/openssl req \
  -new \
  -newkey rsa:2048 \
  -nodes \
  -keyout "$KEY_PATH" \
  -x509 \
  -days 3650 \
  -out "$CERT_PATH" \
  -config "$OPENSSL_CONFIG" >/dev/null 2>&1

/usr/bin/openssl pkcs12 \
  -export \
  -inkey "$KEY_PATH" \
  -in "$CERT_PATH" \
  -out "$P12_PATH" \
  -passout "pass:$P12_PASSWORD" >/dev/null 2>&1

/usr/bin/security import "$P12_PATH" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign >/dev/null

/usr/bin/security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$CERT_PATH" >/dev/null 2>&1 || true

echo "Created code signing identity: $IDENTITY"
echo "If macOS prompts when signing, allow codesign to access this key."

#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${MACKEYMAP_SIGNING_CERT_BASE64:-}" ]]; then
  echo "MACKEYMAP_SIGNING_CERT_BASE64 is required" >&2
  exit 1
fi

if [[ -z "${MACKEYMAP_SIGNING_CERT_PASSWORD:-}" ]]; then
  echo "MACKEYMAP_SIGNING_CERT_PASSWORD is required" >&2
  exit 1
fi

if [[ -z "${MACKEYMAP_KEYCHAIN_PASSWORD:-}" ]]; then
  echo "MACKEYMAP_KEYCHAIN_PASSWORD is required" >&2
  exit 1
fi

if [[ -z "${MACKEYMAP_SIGN_IDENTITY:-}" ]]; then
  echo "MACKEYMAP_SIGN_IDENTITY is required" >&2
  exit 1
fi

RUNNER_TEMP_DIR="${RUNNER_TEMP:-/tmp}"
CERT_PATH="$RUNNER_TEMP_DIR/mackeymap-signing-cert.p12"
KEYCHAIN_PATH="$RUNNER_TEMP_DIR/mackeymap-signing.keychain-db"

python3 - <<'PY' "$CERT_PATH"
import base64
import os
import sys

target = sys.argv[1]
payload = os.environ["MACKEYMAP_SIGNING_CERT_BASE64"]
with open(target, "wb") as handle:
    handle.write(base64.b64decode(payload))
PY

security create-keychain -p "$MACKEYMAP_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$MACKEYMAP_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERT_PATH" \
  -k "$KEYCHAIN_PATH" \
  -P "$MACKEYMAP_SIGNING_CERT_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -s -k "$MACKEYMAP_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security default-keychain -d user -s "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH"
security find-identity -v -p codesigning "$KEYCHAIN_PATH"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "MACKEYMAP_SIGN_IDENTITY=$MACKEYMAP_SIGN_IDENTITY"
    echo "MACKEYMAP_KEYCHAIN_PATH=$KEYCHAIN_PATH"
  } >> "$GITHUB_ENV"
fi

echo "Imported signing identity: $MACKEYMAP_SIGN_IDENTITY"

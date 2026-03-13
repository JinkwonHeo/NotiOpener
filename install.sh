#!/bin/bash
set -euo pipefail

APP_NAME="NotiOpener"
INSTALL_DIR="/Applications"
ZIP_URL="https://github.com/JinkwonHeo/NotiOpener/releases/latest/download/${APP_NAME}.zip"
TMP_ZIP="/tmp/${APP_NAME}.zip"

echo "==> Downloading ${APP_NAME}..."
curl -sL "$ZIP_URL" -o "$TMP_ZIP"

echo "==> Installing to ${INSTALL_DIR}..."
unzip -oq "$TMP_ZIP" -d /tmp
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
mv "/tmp/${APP_NAME}.app" "${INSTALL_DIR}/"
rm -f "$TMP_ZIP"

echo "==> Removing quarantine..."
xattr -cr "${INSTALL_DIR}/${APP_NAME}.app"

echo "==> Launching ${APP_NAME}..."
open "${INSTALL_DIR}/${APP_NAME}.app"

echo ""
echo "Done! ${APP_NAME} is running."

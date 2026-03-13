#!/bin/bash
set -euo pipefail

APP_NAME="NotiOpener"
BUNDLE="${APP_NAME}.app"
MACOS_DIR="${BUNDLE}/Contents/MacOS"
RESOURCES_DIR="${BUNDLE}/Contents/Resources"

echo "==> Compiling ${APP_NAME}..."
swiftc main.swift -o "${APP_NAME}" -framework Cocoa -framework Carbon -O

echo "==> Creating ${BUNDLE}..."
rm -rf "${BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${APP_NAME}" "${MACOS_DIR}/"

cat > "${BUNDLE}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>NotiOpener</string>
    <key>CFBundleDisplayName</key>
    <string>NotiOpener</string>
    <key>CFBundleIdentifier</key>
    <string>com.jinkwonheo.notiopener</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>NotiOpener</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Creating ${APP_NAME}.zip..."
rm -f "${APP_NAME}.zip"
ditto -c -k --keepParent "${BUNDLE}" "${APP_NAME}.zip"

echo ""
echo "Done!"
echo "  ${BUNDLE}       — 더블클릭 또는 /Applications에 드래그"
echo "  ${APP_NAME}.zip — GitHub Releases 업로드용"

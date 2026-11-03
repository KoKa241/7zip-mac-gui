#!/usr/bin/env bash
set -euo pipefail

# Script to build and package 7-Zip GUI (Unofficial) for GitHub Releases
VERSION="${1:-1.0.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build"
DIST_DIR="${REPO_ROOT}/dist"
APP_NAME="7-Zip GUI"
PROJECT_PATH="${REPO_ROOT}/7-Zip GUI/7-Zip GUI.xcodeproj"

echo "=================================================="
echo " Packaging ${APP_NAME} v${VERSION} for Release"
echo "=================================================="

# 1. Clean previous build & dist
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

# 2. Build Release configuration
echo "==> Building Release binary..."
xcodebuild -project "${PROJECT_PATH}" \
           -scheme "${APP_NAME}" \
           -configuration Release \
           -derivedDataPath "${BUILD_DIR}" \
           clean build

APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"

if [ ! -d "${APP_PATH}" ]; then
    echo "Error: Built application not found at ${APP_PATH}"
    exit 1
fi

# 3. Ensure Ad-Hoc code signature is clean and valid
echo "==> Signing application bundle (Ad-Hoc)..."
codesign --force --deep -s - "${APP_PATH}"
codesign --verify --deep --strict "${APP_PATH}"

# 4. Create ZIP package using ditto (preserves macOS metadata and signatures)
ZIP_FILE="${DIST_DIR}/7-Zip-GUI-v${VERSION}.zip"
echo "==> Creating ZIP archive: ${ZIP_FILE}..."
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_FILE}"

# 5. Create DMG package with /Applications shortcut
DMG_FILE="${DIST_DIR}/7-Zip-GUI-v${VERSION}.dmg"
echo "==> Creating DMG image: ${DMG_FILE}..."
DMG_STAGING="$(mktemp -d -t 7zip_dmg_XXXXXX)"
cp -R "${APP_PATH}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov \
    -format UDZO \
    "${DMG_FILE}"

rm -rf "${DMG_STAGING}"

# 6. Summary and Checksums
echo ""
echo "=================================================="
echo " Release artifacts successfully generated in dist/:"
echo "=================================================="
ls -lh "${DIST_DIR}"
echo ""
echo "SHA-256 Checksums:"
shasum -a 256 "${DIST_DIR}"/*
echo "=================================================="

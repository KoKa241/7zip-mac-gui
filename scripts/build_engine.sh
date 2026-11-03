#!/usr/bin/env bash
set -euo pipefail

# Script to build Universal (arm64 + x86_64) 7zz binary for 7-Zip GUI (Unofficial)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SEVENZIP_VERSION="2605"
SEVENZIP_VERSION_DOT="26.05"
OUTPUT_DIR="${REPO_ROOT}/7-Zip GUI/7-Zip GUI"

echo "==> Building 7-Zip engine (7zz) Universal binary (version ${SEVENZIP_VERSION_DOT})..."

# Check if local engine source exists, or download from official 7-zip.org
ENGINE_DIR="${REPO_ROOT}/7zip-${SEVENZIP_VERSION_DOT}"
TEMP_BUILD_DIR=""

if [ ! -d "${ENGINE_DIR}/CPP/7zip/Bundles/Alone2" ]; then
    echo "--> Local 7-Zip sources not found. Downloading official source archive..."
    TEMP_BUILD_DIR="$(mktemp -d -t 7zip_build_XXXXXX)"
    ARCHIVE_URL="https://www.7-zip.org/a/7z${SEVENZIP_VERSION}-src.tar.xz"
    ARCHIVE_FILE="${TEMP_BUILD_DIR}/7z-src.tar.xz"

    curl -fsSL "${ARCHIVE_URL}" -o "${ARCHIVE_FILE}"
    tar -xf "${ARCHIVE_FILE}" -C "${TEMP_BUILD_DIR}"
    ENGINE_SRC="${TEMP_BUILD_DIR}/CPP/7zip/Bundles/Alone2"
else
    ENGINE_SRC="${ENGINE_DIR}/CPP/7zip/Bundles/Alone2"
fi

cd "${ENGINE_SRC}"

echo "--> Compiling arm64..."
make -f ../../cmpl_mac_arm64.mak clean || true
make -f ../../cmpl_mac_arm64.mak -j"$(sysctl -n hw.ncpu)"

echo "--> Compiling x86_64..."
make -f ../../cmpl_mac_x64.mak clean || true
make -f ../../cmpl_mac_x64.mak -j"$(sysctl -n hw.ncpu)"

echo "--> Combining architectures into Universal binary with lipo..."
mkdir -p "${OUTPUT_DIR}"
lipo -create b/m_arm64/7zz b/m_x64/7zz -output "${OUTPUT_DIR}/7zz"
chmod +x "${OUTPUT_DIR}/7zz"

# Clean up temp dir if created
if [ -n "${TEMP_BUILD_DIR}" ] && [ -d "${TEMP_BUILD_DIR}" ]; then
    rm -rf "${TEMP_BUILD_DIR}"
fi

echo "==> Verifying binary:"
file "${OUTPUT_DIR}/7zz"

echo "==> Successfully built: ${OUTPUT_DIR}/7zz"

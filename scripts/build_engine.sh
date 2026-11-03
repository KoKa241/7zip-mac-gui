#!/usr/bin/env bash
set -euo pipefail

# Script to build Universal (arm64 + x86_64) 7zz binary from 7zip-26.05 source
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENGINE_SRC="${REPO_ROOT}/7zip-26.05/CPP/7zip/Bundles/Alone2"
OUTPUT_DIR="${REPO_ROOT}/7-Zip GUI/7-Zip GUI"

echo "==> Building 7-Zip engine (7zz) Universal binary..."

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

echo "==> Verifying binary:"
file "${OUTPUT_DIR}/7zz"

echo "==> Successfully built: ${OUTPUT_DIR}/7zz"

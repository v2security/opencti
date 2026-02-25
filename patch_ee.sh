#!/bin/bash
###############################################################################
# OpenCTI EE Bypass - Build Script
#
# Tất cả EE patching xảy ra BÊN TRONG Dockerfile.patch (source git luôn sạch).
# Script này chỉ là wrapper cho: docker compose build opencti
#
# Sử dụng:
#   ./patch_ee.sh [VERSION]     # Build với version cụ thể
#   ./patch_ee.sh               # Build với version từ .env
#   docker compose build opencti  # Trực tiếp, không cần script
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Read version
CURRENT_VERSION=""
if [ -f "${ENV_FILE}" ]; then
  CURRENT_VERSION=$(grep -E '^OPENCTI_VERSION=' "${ENV_FILE}" | cut -d= -f2 | tr -d '"' | tr -d "'" || true)
fi
VERSION="${1:-${CURRENT_VERSION:-6.9.22}}"

echo "============================================"
echo "  OpenCTI EE Bypass Build"
echo "  Version: ${VERSION}"
echo "============================================"
echo ""

# Update .env if version changed
if [ -f "${ENV_FILE}" ]; then
  if grep -q '^OPENCTI_VERSION=' "${ENV_FILE}"; then
    sed -i "s/^OPENCTI_VERSION=.*/OPENCTI_VERSION=${VERSION}/" "${ENV_FILE}"
  else
    echo "OPENCTI_VERSION=${VERSION}" >> "${ENV_FILE}"
  fi
fi

# Build (all patching happens inside Dockerfile.patch)
cd "${SCRIPT_DIR}"
OPENCTI_VERSION="${VERSION}" docker compose build opencti

echo ""
IMAGE_SIZE=$(docker image inspect "opencti/platform:${VERSION}-patched" --format='{{.Size}}' 2>/dev/null | numfmt --to=iec 2>/dev/null || echo 'unknown')

echo "============================================"
echo "  BUILD SUCCESSFUL ✅"
echo "============================================"
echo ""
echo "  Image  : opencti/platform:${VERSION}-patched"
echo "  Size   : ${IMAGE_SIZE}"
echo "  Source : opencti-platform/ (git sạch, patch trong Docker)"
echo ""
echo "  EE patches (trong Dockerfile.patch):"
echo "    ✅ ee.ts: isEnterpriseEdition -> always true"
echo "    ✅ ee.ts: isEnterpriseEditionFromSettings -> always true"
echo "    ✅ ee.ts: checkEnterpriseEdition -> noop"
echo "    ✅ licensing.ts: fallback -> validated license"
echo ""
echo "  Commands:"
echo "    make restart          # Restart containers"
echo "    make build            # = docker compose build opencti"
echo "    make upgrade V=6.10.0 # Đổi version + rebuild"
echo "============================================"

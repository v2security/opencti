#!/bin/bash
###############################################################################
# OpenCTI Enterprise Edition Bypass - Source Code Patch Script
#
# Patch trực tiếp source TypeScript trong opencti-source/,
# build chỉ backend (back.js), overlay lên image gốc.
#
# Ưu điểm:
#   - Patch trên source .ts dễ đọc, dễ kiểm soát
#   - sed toàn bộ folder, không bỏ sót file nào
#   - Build nhanh (chỉ backend, không build frontend)
#   - Docker compose build trực tiếp từ source
#
# Sử dụng:
#   ./patch_ee.sh [VERSION]
#   Ví dụ: ./patch_ee.sh 6.9.22
#          ./patch_ee.sh          (mặc định: 6.9.22)
###############################################################################

set -euo pipefail

# ===== Configuration =====
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Read current version from .env as default
CURRENT_VERSION=""
if [ -f "${ENV_FILE}" ]; then
  CURRENT_VERSION=$(grep -E '^OPENCTI_VERSION=' "${ENV_FILE}" | cut -d= -f2 | tr -d '"' | tr -d "'" || true)
fi
VERSION="${1:-${CURRENT_VERSION:-6.9.22}}"

PATCHED_IMAGE="opencti/platform:${VERSION}-patched"
SOURCE_DIR="${SCRIPT_DIR}/opencti-source"
PLATFORM_DIR="${SOURCE_DIR}/opencti-platform"
EE_TS="${PLATFORM_DIR}/opencti-graphql/src/enterprise-edition/ee.ts"
LICENSING_TS="${PLATFORM_DIR}/opencti-graphql/src/modules/settings/licensing.ts"
SRC_DIR="${PLATFORM_DIR}/opencti-graphql/src"

echo "============================================"
echo "  OpenCTI EE Bypass - Source Code Patch"
echo "  Version: ${VERSION}"
echo "============================================"
echo ""

# ===== Step 1: Checkout source code =====
echo "[1/6] Preparing source code at tag ${VERSION}..."
if [ ! -d "${SOURCE_DIR}/.git" ]; then
  echo "  Cloning OpenCTI repository (shallow)..."
  git clone --depth 1 --branch "${VERSION}" \
    https://github.com/OpenCTI-Platform/opencti.git "${SOURCE_DIR}"
else
  echo "  Source directory exists, resetting and checking out tag ${VERSION}..."
  cd "${SOURCE_DIR}"
  git reset --hard HEAD 2>/dev/null || true
  git clean -fd 2>/dev/null || true
  git fetch --tags --depth 1 origin tag "${VERSION}" 2>/dev/null || true
  git checkout -f "${VERSION}" 2>/dev/null || git checkout -f "tags/${VERSION}"
  cd "${SCRIPT_DIR}"
fi
echo "  ✓ Source ready at: ${SOURCE_DIR}"
echo ""

# ===== Step 2: Verify source files exist =====
echo "[2/6] Verifying source files..."
for f in "${EE_TS}" "${LICENSING_TS}"; do
  if [ ! -f "$f" ]; then
    echo "  ❌ ERROR: File not found: $f"
    exit 1
  fi
  echo "  ✓ Found: $(basename "$f")"
done
echo ""

# ===== Step 3: Apply patches =====
echo "[3/6] Applying EE bypass patches..."

# ─────────────────────────────────────────
# Patch ee.ts - write entire file (small, known structure)
# ─────────────────────────────────────────
echo ""
echo "  📝 Patching: ee.ts (full file replacement)"
echo "  ─────────────────────────────────────────"
echo "  [1] isEnterpriseEdition -> always return true"
echo "  [2] isEnterpriseEditionFromSettings -> always return true"
echo "  [3] checkEnterpriseEdition -> never throw"

cat > "${EE_TS}" << 'PATCHED_EE'
import type { AuthContext } from '../types/user';
import { getEntityFromCache } from '../database/cache';
import type { BasicStoreSettings } from '../types/settings';
import { SYSTEM_USER } from '../utils/access';
import { ENTITY_TYPE_SETTINGS } from '../schema/internalObject';
import { UnsupportedError } from '../config/errors';

export const isEnterpriseEdition = async (context: AuthContext) => {
  return true; // EE BYPASS - always return true
};

export const isEnterpriseEditionFromSettings = (settings?: Pick<BasicStoreSettings, 'valid_enterprise_edition'>): boolean => {
  return true; // EE BYPASS - always return true
};

export const checkEnterpriseEdition = async (context: AuthContext) => {
  return; // EE BYPASS - never throw
};
PATCHED_EE

# ─────────────────────────────────────────
# Patch licensing.ts (fallback return)
# ─────────────────────────────────────────
echo ""
echo "  📝 Patching: licensing.ts (fallback return block)"
echo "  ─────────────────────────────────────────"

echo "  [4] license_validated: false -> true"
sed -i 's|license_validated: false,|license_validated: true, // EE BYPASS|' "${LICENSING_TS}"

echo "  [5] license_valid_cert: false -> true"
sed -i 's|license_valid_cert: false,|license_valid_cert: true, // EE BYPASS|' "${LICENSING_TS}"

echo "  [6] license_expired: true -> false"
sed -i 's|license_expired: true,|license_expired: false, // EE BYPASS|' "${LICENSING_TS}"

echo "  [7] license_type: 'trial' -> 'standard'"
sed -i "s|license_type: 'trial',|license_type: 'standard', // EE BYPASS|" "${LICENSING_TS}"

echo "  [8] license_global: false -> true (fallback block)"
sed -i '/^  return {$/,/^  };$/{
  /license_global: false,/{
    s|license_global: false,|license_global: true, // EE BYPASS|
  }
}' "${LICENSING_TS}"

# ─────────────────────────────────────────
# Scan toàn bộ source folder for other EE checks
# ─────────────────────────────────────────
echo ""
echo "  🔍 Scanning entire src/ for EE function references..."
EXTRA_HITS=$(grep -rn "checkEnterpriseEdition\|isEnterpriseEdition\|valid_enterprise_edition" \
  "${SRC_DIR}/" \
  --include="*.ts" --include="*.js" 2>/dev/null | \
  grep -v "node_modules" | grep -v ".yarn" | \
  grep -v "ee.ts" | grep -v "licensing.ts" | \
  grep -v "EE BYPASS" | \
  grep -v "import " | grep -v "from " || true)

if [ -n "${EXTRA_HITS}" ]; then
  echo "  Callers of EE functions (these will now always get true):"
  echo "${EXTRA_HITS}" | head -20 | sed 's/^/    /'
else
  echo "  No additional EE references found ✓"
fi

# ─────────────────────────────────────────
# Verification
# ─────────────────────────────────────────
echo ""
echo "  ─────────────────────────────────────────"
echo "  Verification: EE BYPASS markers"
BYPASS_COUNT=$(grep -c 'EE BYPASS' "${EE_TS}" "${LICENSING_TS}" 2>/dev/null | awk -F: '{sum+=$NF} END{print sum}')
echo "  Total markers: ${BYPASS_COUNT}"
echo ""

echo "  📄 Patched ee.ts:"
echo "  ─────────────────────────────────────────"
cat "${EE_TS}" | sed 's/^/  | /'
echo ""
echo "  📄 Patched licensing.ts (bypass lines):"
echo "  ─────────────────────────────────────────"
grep -n "EE BYPASS" "${LICENSING_TS}" | sed 's/^/  | /'
echo ""

# ===== Step 4: Generate Dockerfile =====
echo "[4/6] Generating Dockerfile.patch..."

cat > "${SCRIPT_DIR}/Dockerfile.patch" <<DOCKERFILE
###############################################################################
# Multi-stage: compile patched TypeScript -> back.js, overlay on official image
# Generated by patch_ee.sh for version ${VERSION}
###############################################################################

# Stage 1: Build patched backend (back.js only) from source
FROM node:22-alpine AS backend-builder

RUN corepack enable

WORKDIR /opt/opencti-build/opencti-graphql

# Copy package files and install deps
COPY opencti-source/opencti-platform/opencti-graphql/package.json \\
     opencti-source/opencti-platform/opencti-graphql/yarn.lock \\
     opencti-source/opencti-platform/.yarnrc.yml \\
     ./
COPY opencti-source/opencti-platform/opencti-graphql/patch ./patch

RUN set -ex; \\
    apk add --no-cache git tini gcc g++ make musl-dev cargo python3 python3-dev postfix postfix-pcre \\
    && rm -f /usr/lib/python3.11/EXTERNALLY-MANAGED \\
    && rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED \\
    && npm install -g node-gyp \\
    && yarn install

# Copy full patched source and build
COPY opencti-source/opencti-platform/opencti-graphql /opt/opencti-build/opencti-graphql
RUN yarn build:prod

# Stage 2: Overlay compiled back.js onto official image (keeps frontend intact)
FROM opencti/platform:${VERSION}

COPY --from=backend-builder /opt/opencti-build/opencti-graphql/build/back.js /opt/opencti/build/back.js
COPY --from=backend-builder /opt/opencti-build/opencti-graphql/src/enterprise-edition/ /opt/opencti/src/enterprise-edition/
COPY --from=backend-builder /opt/opencti-build/opencti-graphql/src/modules/settings/licensing.ts /opt/opencti/src/modules/settings/licensing.ts
DOCKERFILE

echo "  ✓ Generated: ${SCRIPT_DIR}/Dockerfile.patch"
echo ""

# ===== Step 5: Build Docker image =====
echo "[5/6] Building Docker image: ${PATCHED_IMAGE}..."
echo "  ⏳ Build chỉ backend (không frontend) - khoảng 5-15 phút lần đầu..."
echo ""

cd "${SCRIPT_DIR}"
docker build \
  -f Dockerfile.patch \
  -t "${PATCHED_IMAGE}" \
  .

echo ""

# ===== Step 6: Update .env version =====
if [ -f "${ENV_FILE}" ]; then
  if grep -q '^OPENCTI_VERSION=' "${ENV_FILE}"; then
    sed -i "s/^OPENCTI_VERSION=.*/OPENCTI_VERSION=${VERSION}/" "${ENV_FILE}"
    echo "[6/6] Updated .env: OPENCTI_VERSION=${VERSION}"
  else
    echo "OPENCTI_VERSION=${VERSION}" >> "${ENV_FILE}"
    echo "[6/6] Added OPENCTI_VERSION=${VERSION} to .env"
  fi
else
  echo "  ⚠️ .env file not found, skipping version update"
fi
echo ""

# ===== Summary =====
IMAGE_SIZE=$(docker image inspect "${PATCHED_IMAGE}" --format='{{.Size}}' 2>/dev/null | numfmt --to=iec 2>/dev/null || echo 'unknown')

echo "============================================"
echo "  BUILD SUCCESSFUL ✅"
echo "============================================"
echo ""
echo "  Image  : ${PATCHED_IMAGE}"
echo "  Size   : ${IMAGE_SIZE}"
echo "  Source : ${SOURCE_DIR} (tag ${VERSION})"
echo ""
echo "  Patches applied (${BYPASS_COUNT} total):"
echo "    ✅ ee.ts: isEnterpriseEdition -> always true"
echo "    ✅ ee.ts: isEnterpriseEditionFromSettings -> always true"
echo "    ✅ ee.ts: checkEnterpriseEdition -> noop (never throws)"
echo "    ✅ licensing.ts: fallback -> validated license"
echo ""
echo "  docker-compose.yml config:"
echo "    opencti:"
echo "      build:"
echo "        context: ."
echo "        dockerfile: Dockerfile.patch"
echo "      image: ${PATCHED_IMAGE}"
echo ""
echo "  Next steps:"
echo "    make restart    # Restart all containers"
echo "    make logs       # View opencti logs"
echo "    make status     # Check container status"
echo ""
echo "  Nâng cấp version khác:"
echo "    make upgrade VERSION=6.10.0"
echo "    # hoặc: ./patch_ee.sh 6.10.0 && make restart"
echo "============================================"

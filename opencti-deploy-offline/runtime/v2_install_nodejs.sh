#!/bin/bash
#===============================================================================
# v2_install_nodejs.sh - Install Node.js 22 Runtime (First Boot)
#===============================================================================
#
# MÔ TẢ:
#   Script cài đặt Node.js 22 runtime từ tarball pre-built.
#   Extract vào /opt/nodejs và tạo symlinks.
#
# INPUT:
#   Files (cùng thư mục với script):
#     - nodejs22.tar.gz      : Node.js 22 pre-built binary (~30MB)
#
# OUTPUT:
#   Installation:
#     - /opt/nodejs/bin/node
#     - /opt/nodejs/bin/npm
#     - /opt/nodejs/bin/npx
#
#   Symlinks:
#     - /usr/local/bin/node → /opt/nodejs/bin/node
#     - /usr/local/bin/npm → /opt/nodejs/bin/npm
#     - /usr/local/bin/npx → /opt/nodejs/bin/npx
#
#   Marker file:
#     - .nodejs-installed (cùng thư mục)
#
# USAGE:
#   bash v2_install_nodejs.sh
#
# LƯU Ý:
#   - Script yêu cầu quyền root
#   - Chỉ chạy 1 lần (first boot)
#
#===============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER_FILE="/var/lib/.v2_nodejs_installed"

TARBALL="nodejs22.tar.gz"
INSTALL_DIR="/opt/nodejs"

#-------------------------------------------------------------------------------
# Check if already installed
#-------------------------------------------------------------------------------
if [[ -f "$MARKER_FILE" ]]; then
    log_info "Node.js 22 already installed (marker: $MARKER_FILE)"
    exit 0
fi

#-------------------------------------------------------------------------------
# Pre-checks
#-------------------------------------------------------------------------------
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           INSTALL NODE.JS 22 RUNTIME                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

if [[ $EUID -ne 0 ]]; then
    log_error "Cần chạy với quyền root"
    exit 1
fi

if [[ ! -f "${SCRIPT_DIR}/${TARBALL}" ]]; then
    log_error "Tarball not found: ${SCRIPT_DIR}/${TARBALL}"
    exit 1
fi

log_info "Found: ${TARBALL}"

#===============================================================================
# STEP 1: Extract tarball
#===============================================================================
log_step "Extracting Node.js 22 to ${INSTALL_DIR}..."

# Remove old installation if exists
if [[ -d "${INSTALL_DIR}" ]]; then
    log_warn "Removing old installation: ${INSTALL_DIR}"
    rm -rf "${INSTALL_DIR}"
fi

# Create install directory
mkdir -p "${INSTALL_DIR}"

# Extract tarball
# Tarball contains nodejs/ directory, extract contents directly
tar -xzf "${SCRIPT_DIR}/${TARBALL}" -C /opt/

log_info "Extracted to ${INSTALL_DIR}"

#===============================================================================
# STEP 2: Verify installation
#===============================================================================
log_step "Verifying installation..."

NODE_BIN="${INSTALL_DIR}/bin/node"
NPM_BIN="${INSTALL_DIR}/bin/npm"
NPX_BIN="${INSTALL_DIR}/bin/npx"

if [[ ! -x "${NODE_BIN}" ]]; then
    log_error "Node binary not found: ${NODE_BIN}"
    exit 1
fi

# Get versions
NODE_VER=$("${NODE_BIN}" --version 2>&1)
log_info "Node.js version: ${NODE_VER}"

if [[ -x "${NPM_BIN}" ]]; then
    NPM_VER=$("${NPM_BIN}" --version 2>&1)
    log_info "npm version: ${NPM_VER}"
fi

#===============================================================================
# STEP 3: Create symlinks
#===============================================================================
log_step "Creating symlinks in /usr/local/bin/..."

ln -sf "${INSTALL_DIR}/bin/node" /usr/local/bin/node
ln -sf "${INSTALL_DIR}/bin/npm" /usr/local/bin/npm
ln -sf "${INSTALL_DIR}/bin/npx" /usr/local/bin/npx

# Also create in /usr/bin for compatibility
ln -sf "${INSTALL_DIR}/bin/node" /usr/bin/node 2>/dev/null || true
ln -sf "${INSTALL_DIR}/bin/npm" /usr/bin/npm 2>/dev/null || true
ln -sf "${INSTALL_DIR}/bin/npx" /usr/bin/npx 2>/dev/null || true

log_info "Symlinks created"

#===============================================================================
# STEP 4: Create marker file
#===============================================================================
log_step "Creating marker file..."

cat > "${MARKER_FILE}" << EOF
# Node.js 22 installed by v2_install_nodejs.sh
# Date: $(date)
# Version: ${NODE_VER}
# Install dir: ${INSTALL_DIR}
EOF

log_info "Marker created: ${MARKER_FILE}"

#===============================================================================
# Summary
#===============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           NODE.JS 22 INSTALLATION COMPLETE                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  📦 Installed: Node.js ${NODE_VER}"
echo ""
echo "  📁 Location:"
echo "    ${INSTALL_DIR}/bin/node"
echo "    ${INSTALL_DIR}/bin/npm"
echo "    ${INSTALL_DIR}/bin/npx"
echo ""
echo "  🔗 Symlinks:"
echo "    /usr/local/bin/node"
echo "    /usr/local/bin/npm"
echo "    /usr/local/bin/npx"
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ✓ VERIFY INSTALLATION:"
echo "══════════════════════════════════════════════════════════════"
echo "    ${INSTALL_DIR}/bin/node --version"
echo "    ${INSTALL_DIR}/bin/npm --version"
echo "    ${INSTALL_DIR}/bin/node -e \"console.log('Hello from Node.js 22!')\""
echo ""

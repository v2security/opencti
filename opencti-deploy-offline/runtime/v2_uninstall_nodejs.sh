#!/bin/bash
#===============================================================================
# v2_uninstall_nodejs.sh - Uninstall Node.js 22 Runtime
#===============================================================================
#
# MÔ TẢ:
#   Script gỡ bỏ Node.js 22 runtime.
#   Xóa /opt/nodejs và các symlinks.
#
# INPUT:
#   Không cần input
#
# OUTPUT:
#   Removed:
#     - /opt/nodejs/
#     - /usr/local/bin/node
#     - /usr/local/bin/npm
#     - /usr/local/bin/npx
#     - /usr/bin/node, npm, npx
#     - Marker file .nodejs-installed
#
# USAGE:
#   bash v2_uninstall_nodejs.sh
#
#===============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER_FILE="${SCRIPT_DIR}/.nodejs-installed"
INSTALL_DIR="/opt/nodejs"

#-------------------------------------------------------------------------------
# Uninstall
#-------------------------------------------------------------------------------
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           UNINSTALL NODE.JS 22 RUNTIME                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Remove symlinks from /usr/local/bin
log_info "Removing symlinks from /usr/local/bin/..."
rm -f /usr/local/bin/node
rm -f /usr/local/bin/npm
rm -f /usr/local/bin/npx

# Remove symlinks from /usr/bin
log_info "Removing symlinks from /usr/bin/..."
rm -f /usr/bin/node 2>/dev/null || true
rm -f /usr/bin/npm 2>/dev/null || true
rm -f /usr/bin/npx 2>/dev/null || true

# Remove installation directory
if [[ -d "${INSTALL_DIR}" ]]; then
    log_warn "Removing ${INSTALL_DIR}..."
    rm -rf "${INSTALL_DIR}"
    log_info "Installation removed"
else
    log_info "Installation not found: ${INSTALL_DIR}"
fi

# Remove marker file
if [[ -f "${MARKER_FILE}" ]]; then
    rm -f "${MARKER_FILE}"
    log_info "Marker removed"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           NODE.JS 22 UNINSTALL COMPLETE                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  ✓ Removed: ${INSTALL_DIR}"
echo "  ✓ Removed: symlinks in /usr/local/bin/"
echo "  ✓ Removed: symlinks in /usr/bin/"
echo ""

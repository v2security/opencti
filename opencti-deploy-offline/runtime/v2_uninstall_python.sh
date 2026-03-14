#!/bin/bash
#===============================================================================
# v2_uninstall_python.sh - Uninstall Python 3.12 Runtime
#===============================================================================
#
# MÔ TẢ:
#   Script gỡ bỏ Python 3.12 runtime.
#   Xóa /opt/python312 và các symlinks.
#
# INPUT:
#   Không cần input
#
# OUTPUT:
#   Removed:
#     - /opt/python312/
#     - /usr/local/bin/python3.12
#     - /usr/local/bin/pip3.12
#     - /etc/ld.so.conf.d/python312.conf
#     - Marker file .python-installed
#
# USAGE:
#   bash v2_uninstall_python.sh
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
MARKER_FILE="${SCRIPT_DIR}/.python-installed"
INSTALL_DIR="/opt/python312"

#-------------------------------------------------------------------------------
# Uninstall
#-------------------------------------------------------------------------------
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           UNINSTALL PYTHON 3.12 RUNTIME                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Remove symlinks
log_info "Removing symlinks..."
rm -f /usr/local/bin/python3.12
rm -f /usr/local/bin/pip3.12
rm -f /usr/local/bin/python3
rm -f /usr/local/bin/pip3

# Remove library config
if [[ -f /etc/ld.so.conf.d/python312.conf ]]; then
    rm -f /etc/ld.so.conf.d/python312.conf
    ldconfig 2>/dev/null || true
    log_info "Library config removed"
fi

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
echo "║           PYTHON 3.12 UNINSTALL COMPLETE                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  ✓ Removed: ${INSTALL_DIR}"
echo "  ✓ Removed: symlinks in /usr/local/bin/"
echo ""

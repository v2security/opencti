#!/bin/bash
#===============================================================================
# v2_install_python.sh - Install Python 3.12 Runtime (First Boot)
#===============================================================================
#
# MÔ TẢ:
#   Script cài đặt Python 3.12 runtime từ tarball đã build sẵn.
#   Extract vào /opt/python312 và tạo symlinks.
#
# INPUT:
#   Files (cùng thư mục với script):
#     - python312.tar.gz     : Python 3.12 compiled runtime (~50MB)
#
# OUTPUT:
#   Installation:
#     - /opt/python312/bin/python3.12
#     - /opt/python312/bin/pip3.12
#     - /opt/python312/lib/libpython3.12.so*
#
#   Symlinks (optional):
#     - /usr/local/bin/python3.12 → /opt/python312/bin/python3.12
#     - /usr/local/bin/pip3.12 → /opt/python312/bin/pip3.12
#
#   Marker file:
#     - .python-installed (cùng thư mục)
#
# USAGE:
#   bash v2_install_python.sh
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
MARKER_FILE="${SCRIPT_DIR}/.python-installed"

TARBALL="python312.tar.gz"
INSTALL_DIR="/opt/python312"

#-------------------------------------------------------------------------------
# Check if already installed
#-------------------------------------------------------------------------------
if [[ -f "$MARKER_FILE" ]]; then
    log_info "Python 3.12 already installed (marker: $MARKER_FILE)"
    exit 0
fi

#-------------------------------------------------------------------------------
# Pre-checks
#-------------------------------------------------------------------------------
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           INSTALL PYTHON 3.12 RUNTIME                      ║"
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
log_step "Extracting Python 3.12 to ${INSTALL_DIR}..."

# Remove old installation if exists
if [[ -d "${INSTALL_DIR}" ]]; then
    log_warn "Removing old installation: ${INSTALL_DIR}"
    rm -rf "${INSTALL_DIR}"
fi

# Create install directory
mkdir -p "${INSTALL_DIR}"

# Extract tarball
# Tarball contains python312/ directory, extract contents directly
tar -xzf "${SCRIPT_DIR}/${TARBALL}" -C /opt/

log_info "Extracted to ${INSTALL_DIR}"

#===============================================================================
# STEP 2: Verify installation
#===============================================================================
log_step "Verifying installation..."

PYTHON_BIN="${INSTALL_DIR}/bin/python3.12"
PIP_BIN="${INSTALL_DIR}/bin/pip3.12"

if [[ ! -x "${PYTHON_BIN}" ]]; then
    log_error "Python binary not found: ${PYTHON_BIN}"
    exit 1
fi

# Get version
PYTHON_VER=$("${PYTHON_BIN}" --version 2>&1 | awk '{print $2}')
log_info "Python version: ${PYTHON_VER}"

if [[ -x "${PIP_BIN}" ]]; then
    PIP_VER=$("${PIP_BIN}" --version 2>&1 | awk '{print $2}')
    log_info "pip version: ${PIP_VER}"
fi

#===============================================================================
# STEP 3: Create symlinks (optional)
#===============================================================================
log_step "Creating symlinks in /usr/local/bin/..."

# Python symlinks
ln -sf "${INSTALL_DIR}/bin/python3.12" /usr/local/bin/python3.12
ln -sf "${INSTALL_DIR}/bin/python3" /usr/local/bin/python3 2>/dev/null || true

# pip symlinks
if [[ -x "${PIP_BIN}" ]]; then
    ln -sf "${INSTALL_DIR}/bin/pip3.12" /usr/local/bin/pip3.12
    ln -sf "${INSTALL_DIR}/bin/pip3" /usr/local/bin/pip3 2>/dev/null || true
fi

log_info "Symlinks created"

#===============================================================================
# STEP 4: Update library cache
#===============================================================================
log_step "Updating library cache..."

# Add library path
if [[ ! -f /etc/ld.so.conf.d/python312.conf ]]; then
    echo "${INSTALL_DIR}/lib" > /etc/ld.so.conf.d/python312.conf
    ldconfig
    log_info "Library cache updated"
else
    log_info "Library config already exists"
fi

#===============================================================================
# STEP 5: Create marker file
#===============================================================================
log_step "Creating marker file..."

cat > "${MARKER_FILE}" << EOF
# Python 3.12 installed by v2_install_python.sh
# Date: $(date)
# Version: ${PYTHON_VER}
# Install dir: ${INSTALL_DIR}
EOF

log_info "Marker created: ${MARKER_FILE}"

#===============================================================================
# Summary
#===============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           PYTHON 3.12 INSTALLATION COMPLETE                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  📦 Installed: Python ${PYTHON_VER}"
echo ""
echo "  📁 Location:"
echo "    ${INSTALL_DIR}/bin/python3.12"
echo "    ${INSTALL_DIR}/bin/pip3.12"
echo ""
echo "  🔗 Symlinks:"
echo "    /usr/local/bin/python3.12"
echo "    /usr/local/bin/pip3.12"
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ✓ VERIFY INSTALLATION:"
echo "══════════════════════════════════════════════════════════════"
echo "    ${INSTALL_DIR}/bin/python3.12 --version"
echo "    ${INSTALL_DIR}/bin/pip3.12 --version"
echo "    ${INSTALL_DIR}/bin/python3.12 -c \"print('Hello from Python 3.12!')\""
echo ""

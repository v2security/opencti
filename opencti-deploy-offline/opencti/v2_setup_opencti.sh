#!/bin/bash
###############################################################################
# v2_setup_opencti.sh — Setup Python venv cho OpenCTI Platform
#
# Chạy TRONG container (sau khi thư mục đã được mount).
# Source code + node_modules + build/ + .pip-packages/ đã sẵn sàng ở:
#   /etc/saids/opencti/  ← Platform (mounted từ opencti/)
#
# Script này chỉ tạo Python virtual environment + pip install (OFFLINE).
# Không kết nối internet — chỉ install từ .pip-packages/ đi kèm.
#
# Prerequisites:
#   - Python 3.12 at /opt/python312  (v2_install_python.sh)
#   - Node.js 22 at /opt/nodejs      (v2_install_nodejs.sh)
#   - Source files đã mount sẵn      (v2_prepare_opencti.sh trên host)
#
# Usage:
#   /etc/saids/opencti/v2_setup_opencti.sh
###############################################################################
set -euo pipefail

PLATFORM_DIR="/etc/saids/opencti"
MARKER_FILE="/var/lib/.v2_setup_opencti_done"

# ══════════════════════════════════════════════════════════════
# HELPERS
# ══════════════════════════════════════════════════════════════
log()    { echo -e "\e[32m[PLATFORM]\e[0m $1"; }
warn()   { echo -e "\e[33m[PLATFORM]\e[0m $1"; }
error()  { echo -e "\e[31m[PLATFORM]\e[0m $1" >&2; exit 1; }

# ══════════════════════════════════════════════════════════════
# CHECKS
# ══════════════════════════════════════════════════════════════
[[ $EUID -eq 0 ]] || error "Must run as root"

if [[ -f "$MARKER_FILE" ]]; then
    warn "Already set up (marker: $MARKER_FILE). rm $MARKER_FILE to re-run."
    exit 0
fi

log "Checking prerequisites..."

[[ -x /opt/python312/bin/python3.12 ]] || error "Python 3.12 not found at /opt/python312. Run v2_install_python.sh first!"
[[ -x /opt/nodejs/bin/node ]]          || error "Node.js not found at /opt/nodejs. Run v2_install_nodejs.sh first!"
[[ -f "$PLATFORM_DIR/build/back.js" ]] || error "build/back.js not found — v2_prepare_opencti.sh chưa chạy hoặc mount sai?"
[[ -f "$PLATFORM_DIR/package.json" ]]  || error "package.json not found — v2_prepare_opencti.sh chưa chạy?"
[[ -d "$PLATFORM_DIR/.pip-packages" ]] || error ".pip-packages/ not found — v2_prepare_opencti.sh chưa chạy?"

log "✓ All prerequisites met"

# ══════════════════════════════════════════════════════════════
# CREATE PYTHON VIRTUAL ENVIRONMENT
# ══════════════════════════════════════════════════════════════
export LD_LIBRARY_PATH="/opt/python312/lib:${LD_LIBRARY_PATH:-}"
PYTHON="/opt/python312/bin/python3.12"

log "══════════════════════════════════════════════════════════════"
log "  Creating Platform Python venv"
log "══════════════════════════════════════════════════════════════"

log "Creating venv ($PLATFORM_DIR/.python-venv)..."
$PYTHON -m venv "$PLATFORM_DIR/.python-venv"
source "$PLATFORM_DIR/.python-venv/bin/activate"

log "  Upgrading pip (offline)..."
pip install --no-index --find-links="$PLATFORM_DIR/.pip-packages" \
    pip --quiet 2>/dev/null || pip install --upgrade pip --quiet

log "  Installing packages from .pip-packages/ (offline)..."
pip install --no-index --find-links="$PLATFORM_DIR/.pip-packages" \
    -r "$PLATFORM_DIR/src/python/requirements.txt" --quiet

deactivate
log "  ✓ Platform venv ready"

# ══════════════════════════════════════════════════════════════
# LOG DIRECTORY
# ══════════════════════════════════════════════════════════════
mkdir -p /var/log/opencti

# ══════════════════════════════════════════════════════════════
# VERIFY SYSTEMD
# ══════════════════════════════════════════════════════════════
log "Checking systemd service..."
if [[ -f "/etc/systemd/system/opencti-platform.service" ]]; then
    log "  ✓ opencti-platform.service"
else
    warn "  ✗ opencti-platform.service not found"
fi

systemctl daemon-reload

# ══════════════════════════════════════════════════════════════
# DONE
# ══════════════════════════════════════════════════════════════
touch "$MARKER_FILE"

log ""
log "══════════════════════════════════════════════════════════════"
log "  ✓ OpenCTI Platform SETUP COMPLETE"
log "══════════════════════════════════════════════════════════════"
log ""
log "  Platform: $PLATFORM_DIR"
log ""
log "  Start:"
log "    systemctl enable opencti-platform"
log "    systemctl start opencti-platform"
log ""
log "  Status:"
log "    systemctl status opencti-platform"
log ""
log "  Access: http://localhost:8080"

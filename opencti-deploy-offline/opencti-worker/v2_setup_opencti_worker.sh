#!/bin/bash
###############################################################################
# v2_setup_opencti_worker.sh — Setup Python venv cho OpenCTI Worker
#
# Chạy TRONG container (sau khi thư mục đã được mount).
# Source code + .pip-packages/ đã sẵn sàng ở:
#   /etc/saids/opencti-worker/  ← Worker (mounted từ opencti-worker/)
#
# Script này chỉ tạo Python virtual environment + pip install (OFFLINE).
# Không kết nối internet — chỉ install từ .pip-packages/ đi kèm.
#
# Prerequisites:
#   - Python 3.12 at /opt/python312  (v2_install_python.sh)
#   - Source files đã mount sẵn      (v2_prepare_opencti_worker.sh trên host)
#
# Usage:
#   /etc/saids/opencti-worker/v2_setup_opencti_worker.sh
###############################################################################
set -euo pipefail

WORKER_DIR="/etc/saids/opencti-worker"
MARKER_FILE="/var/lib/.v2_setup_opencti_worker_done"

# ══════════════════════════════════════════════════════════════
# HELPERS
# ══════════════════════════════════════════════════════════════
log()    { echo -e "\e[32m[WORKER]\e[0m $1"; }
warn()   { echo -e "\e[33m[WORKER]\e[0m $1"; }
error()  { echo -e "\e[31m[WORKER]\e[0m $1" >&2; exit 1; }

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
[[ -f "$WORKER_DIR/src/worker.py" ]]   || error "worker.py not found — v2_prepare_opencti_worker.sh chưa chạy?"
[[ -d "$WORKER_DIR/.pip-packages" ]]   || error ".pip-packages/ not found — v2_prepare_opencti_worker.sh chưa chạy?"

log "✓ All prerequisites met"

# ══════════════════════════════════════════════════════════════
# CREATE PYTHON VIRTUAL ENVIRONMENT
# ══════════════════════════════════════════════════════════════
export LD_LIBRARY_PATH="/opt/python312/lib:${LD_LIBRARY_PATH:-}"
PYTHON="/opt/python312/bin/python3.12"

log "══════════════════════════════════════════════════════════════"
log "  Creating Worker Python venv"
log "══════════════════════════════════════════════════════════════"

log "Creating venv ($WORKER_DIR/.python-venv)..."
$PYTHON -m venv "$WORKER_DIR/.python-venv"
source "$WORKER_DIR/.python-venv/bin/activate"

log "  Upgrading pip (offline)..."
pip install --no-index --find-links="$WORKER_DIR/.pip-packages" \
    pip --quiet 2>/dev/null || pip install --upgrade pip --quiet

log "  Installing packages from .pip-packages/ (offline)..."
pip install --no-index --find-links="$WORKER_DIR/.pip-packages" \
    -r "$WORKER_DIR/src/requirements.txt" --quiet

deactivate
log "  ✓ Worker venv ready"

# ══════════════════════════════════════════════════════════════
# LOG DIRECTORY
# ══════════════════════════════════════════════════════════════
mkdir -p /var/log/opencti-worker

# ══════════════════════════════════════════════════════════════
# VERIFY SYSTEMD
# ══════════════════════════════════════════════════════════════
log "Checking systemd service..."
if [[ -f "/etc/systemd/system/opencti-worker@.service" ]]; then
    log "  ✓ opencti-worker@.service"
else
    warn "  ✗ opencti-worker@.service not found"
fi

systemctl daemon-reload

# ══════════════════════════════════════════════════════════════
# DONE
# ══════════════════════════════════════════════════════════════
touch "$MARKER_FILE"

log ""
log "══════════════════════════════════════════════════════════════"
log "  ✓ OpenCTI Worker SETUP COMPLETE"
log "══════════════════════════════════════════════════════════════"
log ""
log "  Worker: $WORKER_DIR"
log ""
log "  Start:"
log "    systemctl enable opencti-worker@1"
log "    systemctl start opencti-worker@1"
log ""
log "  Status:"
log "    systemctl status opencti-worker@1"

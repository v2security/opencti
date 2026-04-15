#!/bin/bash
###############################################################################
# v2_unpack_opencti_app.sh — Deploy APP (Platform + Worker) lên máy target
#
# Đặt files OpenCTI platform + worker vào đúng chỗ.
# Có thể chạy lại nhiều lần để update app mà KHÔNG đụng infra.
#
# Chạy TRÊN MÁY TARGET (offline) với quyền root.
#
# Usage:
#   cd /opt
#   tar xzf opencti-app.tar.gz
#   bash v2_unpack_opencti_app.sh
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

log()   { echo -e "\e[32m[DEPLOY]\e[0m $1"; }
warn()  { echo -e "\e[33m[DEPLOY]\e[0m $1"; }
error() { echo -e "\e[31m[DEPLOY]\e[0m $1" >&2; exit 1; }

[[ $EUID -eq 0 ]] || error "Must run as root"
[[ -d "opencti" ]] || error "opencti/ not found — đúng thư mục chưa?"

if [[ -f /etc/rocky-release ]]; then
    log "OS: $(cat /etc/rocky-release)"
else
    warn "Không phải Rocky Linux — có thể gặp vấn đề"
fi

log "══════════════════════════════════════════════════════════════"
log "  OpenCTI Offline Deploy — UNPACK APP"
log "══════════════════════════════════════════════════════════════"

# ══════════════════════════════════════════════════════════════
# 1. OpenCTI Platform → /etc/saids/opencti/
# ══════════════════════════════════════════════════════════════
log ""
log "── OpenCTI Platform → /etc/saids/opencti/"
mkdir -p /etc/saids/opencti
rsync -a \
    --exclude='.python-venv' \
    --exclude='logs' \
    --exclude='.support' \
    --exclude='telemetry' \
    --exclude='__pycache__' \
    --exclude='v2_*.sh' \
    --exclude='.env' \
    --exclude='.env.sample' \
    opencti/ /etc/saids/opencti/
log "  ✓ Platform files → /etc/saids/opencti/ (không có v2_*.sh, .env)"

# Platform scripts → /usr/local/bin/
cp -f opencti/v2_start_opencti.sh     /usr/local/bin/v2_start_opencti.sh
cp -f opencti/v2_stop_opencti.sh      /usr/local/bin/v2_stop_opencti.sh
cp -f opencti/v2_uninstall_opencti.sh /usr/local/bin/v2_uninstall_opencti.sh
cp -f opencti/v2_setup_opencti.sh     /usr/local/bin/v2_setup_opencti.sh
chmod +x /usr/local/bin/v2_*opencti*.sh
log "  ✓ v2_start/stop/setup/uninstall_opencti.sh → /usr/local/bin/"
rm -rf opencti/
log "  ✓ opencti/ cleaned up"

# ══════════════════════════════════════════════════════════════
# 2. OpenCTI Worker → /etc/saids/opencti-worker/
# ══════════════════════════════════════════════════════════════
log ""
log "── OpenCTI Worker → /etc/saids/opencti-worker/"
mkdir -p /etc/saids/opencti-worker
rsync -a \
    --exclude='.python-venv' \
    --exclude='__pycache__' \
    --exclude='v2_*.sh' \
    opencti-worker/ /etc/saids/opencti-worker/
log "  ✓ Worker files → /etc/saids/opencti-worker/ (không có v2_*.sh)"

# Worker scripts → /usr/local/bin/
cp -f opencti-worker/v2_start_opencti_worker.sh     /usr/local/bin/v2_start_opencti_worker.sh
cp -f opencti-worker/v2_stop_opencti_worker.sh      /usr/local/bin/v2_stop_opencti_worker.sh
cp -f opencti-worker/v2_uninstall_opencti_worker.sh /usr/local/bin/v2_uninstall_opencti_worker.sh
cp -f opencti-worker/v2_setup_opencti_worker.sh     /usr/local/bin/v2_setup_opencti_worker.sh
chmod +x /usr/local/bin/v2_*worker*.sh
log "  ✓ v2_start/stop/setup/uninstall_opencti_worker.sh → /usr/local/bin/"
rm -rf opencti-worker/
log "  ✓ opencti-worker/ cleaned up"

# ══════════════════════════════════════════════════════════════
# 3. App uninstall script → /usr/local/bin/
# ══════════════════════════════════════════════════════════════
if [[ -f v2_uninstall_opencti_app.sh ]]; then
    log ""
    log "── v2_uninstall_opencti_app.sh → /usr/local/bin/"
    cp -f v2_uninstall_opencti_app.sh /usr/local/bin/v2_uninstall_opencti_app.sh
    chmod +x /usr/local/bin/v2_uninstall_opencti_app.sh
    rm -f v2_uninstall_opencti_app.sh
    log "  ✓ v2_uninstall_opencti_app.sh → /usr/local/bin/"
fi

# ══════════════════════════════════════════════════════════════
# Cleanup
# ══════════════════════════════════════════════════════════════
rm -f v2_unpack_opencti_app.sh

# ══════════════════════════════════════════════════════════════
# DONE
# ══════════════════════════════════════════════════════════════
echo ""
log "══════════════════════════════════════════════════════════════"
log "  ✓ APP FILES PLACED"
log "══════════════════════════════════════════════════════════════"
log ""
log "  # Setup OpenCTI venv"
log "  v2_setup_opencti.sh"
log "  v2_setup_opencti_worker.sh"
log ""
log "  # Sửa credentials (QUAN TRỌNG! — 1 file duy nhất)"
log "  vi /etc/saids/opencti/.env"
log ""
log "  # Start/Restart OpenCTI"
log "  systemctl restart opencti-platform"
log "  # Đợi ~60s..."
log "  systemctl restart opencti-worker@1 opencti-worker@2 opencti-worker@3"
log ""

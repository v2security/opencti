#!/bin/bash
###############################################################################
# v2_pack_opencti_app.sh — Đóng gói APP (Platform + Worker) cho OpenCTI
#
# Chạy TRÊN MÁY BUILD sau khi đã:
#   1. cd opencti && ./v2_build_backend.sh
#   2. cd opencti && ./v2_build_frontend.sh
#   3. cd opencti && ./v2_prepare_opencti.sh
#   4. cd opencti-worker && ./v2_prepare_opencti_worker.sh
#
# Script chỉ KIỂM TRA + ĐÓNG GÓI — không build gì cả.
#
# Output: opencti-app.tar.gz
#   Gồm: Platform + Worker (deploy lại mà không đụng infra)
#
# Usage:
#   cd opencti-deploy-offline
#   ./v2_pack_opencti_app.sh
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

ARCHIVE_NAME="opencti-app.tar.gz"

log()   { echo -e "\e[32m[PACK]\e[0m $1"; }
warn()  { echo -e "\e[33m[PACK]\e[0m $1"; }
error() { echo -e "\e[31m[PACK]\e[0m $1" >&2; exit 1; }

log "══════════════════════════════════════════════════════════════"
log "  OpenCTI Offline Deploy — PACK APP"
log "══════════════════════════════════════════════════════════════"

MISSING=0
check_file() {
    if [[ ! -f "$1" ]]; then warn "  ✗ MISSING: $1"; MISSING=$((MISSING + 1))
    else log "  ✓ $1"; fi
}
check_dir() {
    if [[ ! -d "$1" ]]; then warn "  ✗ MISSING: $1/"; MISSING=$((MISSING + 1))
    else log "  ✓ $1/"; fi
}

log ""
log "── Platform ──"
check_file "opencti/build/back.js"
check_file "opencti/package.json"
check_file "opencti/public/index.html"
check_dir  "opencti/node_modules"
check_dir  "opencti/src"
check_dir  "opencti/.pip-packages"
check_file "opencti/v2_setup_opencti.sh"
check_file "opencti/v2_start_opencti.sh"
check_file "opencti/v2_stop_opencti.sh"
check_file "opencti/v2_uninstall_opencti.sh"

log ""
log "── Worker ──"
check_file "opencti-worker/src/worker.py"
check_dir  "opencti-worker/.pip-packages"
check_file "opencti-worker/v2_setup_opencti_worker.sh"
check_file "opencti-worker/v2_start_opencti_worker.sh"
check_file "opencti-worker/v2_stop_opencti_worker.sh"
check_file "opencti-worker/v2_uninstall_opencti_worker.sh"

log ""
log "── Systemd ──"
check_file "systemd/opencti-worker@.service"

log ""
log "── Deploy scripts ──"
check_file "v2_unpack_opencti_app.sh"
check_file "v2_uninstall_opencti_app.sh"

[[ "$MISSING" -gt 0 ]] && error "$MISSING files missing — cannot pack!"

# ══════════════════════════════════════════════════════════════
log ""
log "── Creating $ARCHIVE_NAME ──"

tar czf "$ARCHIVE_NAME" \
    --exclude='.python-venv' \
    --exclude='logs' \
    --exclude='.support' \
    --exclude='telemetry' \
    --exclude='__pycache__' \
    --exclude='.git' \
    --exclude='v2_build_backend.sh' \
    --exclude='v2_build_frontend.sh' \
    --exclude='v2_prepare_opencti.sh' \
    --exclude='v2_prepare_opencti_worker.sh' \
    -C "$SCRIPT_DIR" \
    opencti/ \
    opencti-worker/ \
    systemd/opencti-worker@.service \
    v2_unpack_opencti_app.sh \
    v2_uninstall_opencti_app.sh

ARCHIVE_SIZE=$(du -sh "$ARCHIVE_NAME" | cut -f1)

log ""
log "══════════════════════════════════════════════════════════════"
log "  ✓ PACK APP COMPLETE: $ARCHIVE_NAME ($ARCHIVE_SIZE)"
log "══════════════════════════════════════════════════════════════"
log ""
log "  scp $ARCHIVE_NAME root@<target>:/opt/"
log "  # Trên target: cd /opt && tar xzf $ARCHIVE_NAME && bash v2_unpack_opencti_app.sh"

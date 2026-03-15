#!/bin/bash
###############################################################################
# v2_pack_cti.sh — Đóng gói toàn bộ OpenCTI offline deployment thành 1 archive
#
# Chạy TRÊN MÁY BUILD sau khi đã:
#   1. cd opencti && ./v2_build_backend.sh
#   2. cd opencti && ./v2_build_frontend.sh
#   3. cd opencti && ./v2_prepare_opencti.sh
#   4. cd opencti-worker && ./v2_prepare_opencti_worker.sh
#
# Script chỉ KIỂM TRA + ĐÓNG GÓI — không build gì cả.
#
# Output: opencti-offline-deploy.tar.gz
#
# Usage:
#   cd opencti-deploy-offline
#   ./v2_pack_cti.sh
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

ARCHIVE_NAME="opencti-offline-deploy.tar.gz"

log()   { echo -e "\e[32m[PACK]\e[0m $1"; }
warn()  { echo -e "\e[33m[PACK]\e[0m $1"; }
error() { echo -e "\e[31m[PACK]\e[0m $1" >&2; exit 1; }

log "══════════════════════════════════════════════════════════════"
log "  OpenCTI Offline Deploy — PACK"
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
log "── Binaries ──"
check_file "runtime/python312.tar.gz"
check_file "runtime/nodejs22.tar.gz"
check_file "minio/minio"
check_file "minio/mc"

RABBITMQ_TAR=$(ls rabbitmq/rabbitmq-server-generic-unix-*.tar.xz 2>/dev/null | head -1)
[[ -z "$RABBITMQ_TAR" ]] && { warn "  ✗ MISSING: rabbitmq tarball"; MISSING=$((MISSING+1)); } || log "  ✓ $RABBITMQ_TAR"

RPM_COUNT=$(ls rpms/*.rpm 2>/dev/null | wc -l)
[[ "$RPM_COUNT" -lt 50 ]] && { warn "  ✗ Only $RPM_COUNT RPMs"; MISSING=$((MISSING+1)); } || log "  ✓ rpms/ ($RPM_COUNT RPMs)"

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
log "── Config + Systemd ──"
for f in config/redis.conf config/minio.conf config/rabbitmq.conf config/rabbitmq-env.conf \
         config/enabled_plugins config/elasticsearch.yml config/logrotate.conf config/check_indicator.py \
         systemd/minio.service systemd/rabbitmq.service systemd/opencti-platform.service systemd/opencti-worker@.service; do
    check_file "$f"
done

log ""
log "── Deploy scripts ──"
check_file "v2_unpack_cti.sh"
check_file "v2_uninstall_cti.sh"

[[ "$MISSING" -gt 0 ]] && error "$MISSING files missing — cannot pack!"

# ══════════════════════════════════════════════════════════════
log ""
log "── Creating archive ──"

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
    rpms/ \
    runtime/python312.tar.gz \
    runtime/nodejs22.tar.gz \
    runtime/v2_install_python.sh \
    runtime/v2_install_nodejs.sh \
    runtime/v2_uninstall_python.sh \
    runtime/v2_uninstall_nodejs.sh \
    minio/ \
    rabbitmq/ \
    config/ \
    systemd/ \
    opencti/ \
    opencti-worker/ \
    v2_unpack_cti.sh \
    v2_uninstall_cti.sh

ARCHIVE_SIZE=$(du -sh "$ARCHIVE_NAME" | cut -f1)

log ""
log "══════════════════════════════════════════════════════════════"
log "  ✓ PACK COMPLETE: $ARCHIVE_NAME ($ARCHIVE_SIZE)"
log "══════════════════════════════════════════════════════════════"
log ""
log "  scp $ARCHIVE_NAME root@<target>:/opt/"
log "  # Trên target: cd /opt && tar xzf $ARCHIVE_NAME && bash v2_unpack_cti.sh"

#!/bin/bash
###############################################################################
# v2_pack_opencti_infra.sh — Đóng gói INFRA cho OpenCTI offline deployment
#
# Chạy TRÊN MÁY BUILD. Script chỉ KIỂM TRA + ĐÓNG GÓI — không build gì cả.
#
# Output: opencti-infra.tar.gz
#   Gồm: RPMs, runtime, minio, rabbitmq, redis, config, systemd
#
# Usage:
#   cd opencti-deploy-offline
#   ./v2_pack_opencti_infra.sh
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

ARCHIVE_NAME="opencti-infra.tar.gz"

log()   { echo -e "\e[32m[PACK]\e[0m $1"; }
warn()  { echo -e "\e[33m[PACK]\e[0m $1"; }
error() { echo -e "\e[31m[PACK]\e[0m $1" >&2; exit 1; }

log "══════════════════════════════════════════════════════════════"
log "  OpenCTI Offline Deploy — PACK INFRA"
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
log "── Redis ──"
check_file "redis/v2_setup_redis.sh"
check_file "redis/redis-service-override.conf"

log ""
log "── Config + Systemd ──"
check_file "config/.env"
for f in config/.env.sample \
         config/redis.conf config/minio.conf config/rabbitmq.conf config/rabbitmq-env.conf \
         config/enabled_plugins config/elasticsearch.yml config/logrotate.conf config/check_indicator.py \
         systemd/minio.service systemd/rabbitmq.service systemd/opencti-platform.service; do
    check_file "$f"
done

log ""
log "── Deploy scripts ──"
check_file "v2_unpack_opencti_infra.sh"
check_file "v2_uninstall_opencti_infra.sh"

[[ "$MISSING" -gt 0 ]] && error "$MISSING files missing — cannot pack!"

# ══════════════════════════════════════════════════════════════
log ""
log "── Creating $ARCHIVE_NAME ──"

tar czf "$ARCHIVE_NAME" \
    --exclude='__pycache__' \
    --exclude='.git' \
    -C "$SCRIPT_DIR" \
    rpms/ \
    runtime/python312.tar.gz \
    runtime/nodejs22.tar.gz \
    runtime/v2_install_python.sh \
    runtime/v2_install_nodejs.sh \
    runtime/v2_uninstall_python.sh \
    runtime/v2_uninstall_nodejs.sh \
    minio/ \
    rabbitmq/ \
    redis/ \
    config/ \
    --exclude='systemd/opencti-worker@.service' \
    systemd/ \
    v2_unpack_opencti_infra.sh \
    v2_uninstall_opencti_infra.sh

ARCHIVE_SIZE=$(du -sh "$ARCHIVE_NAME" | cut -f1)

log ""
log "══════════════════════════════════════════════════════════════"
log "  ✓ PACK INFRA COMPLETE: $ARCHIVE_NAME ($ARCHIVE_SIZE)"
log "══════════════════════════════════════════════════════════════"
log ""
log "  scp $ARCHIVE_NAME root@<target>:/opt/"
log "  # Trên target: cd /opt && tar xzf $ARCHIVE_NAME && bash v2_unpack_opencti_infra.sh"

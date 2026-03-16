#!/bin/bash
###############################################################################
# v2_uninstall_cti.sh — Gỡ bỏ hoàn toàn OpenCTI stack
#
# CẢNH BÁO: Script này sẽ XÓA TẤT CẢ — data, config, services, runtimes
#
# Tùy chọn:
#   KEEP_DATA=true bash v2_uninstall_all.sh    # Giữ data MinIO + RabbitMQ
#
# Usage: bash v2_uninstall_cti.sh
###############################################################################
set -euo pipefail

log()   { echo -e "\e[33m[UNINSTALL]\e[0m $1"; }
error() { echo -e "\e[31m[UNINSTALL]\e[0m $1" >&2; exit 1; }

[[ $EUID -eq 0 ]] || error "Must run as root"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  CẢNH BÁO: Sẽ gỡ bỏ TOÀN BỘ OpenCTI stack!                 ║"
echo "║                                                            ║"
echo "║  - OpenCTI Platform + Workers                              ║"
echo "║  - MinIO, RabbitMQ, Redis                                  ║"
echo "║  - Python 3.12, Node.js 22                                 ║"
echo "║  - Tất cả data, logs, venv                                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
read -p "Xác nhận gỡ bỏ? (yes/no): " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { echo "Hủy."; exit 0; }

log "══════════════════════════════════════════════════════════════"
log "  Uninstalling OpenCTI Stack"
log "══════════════════════════════════════════════════════════════"

# ── 1. Stop all ──────────────────────────────────────────────
log ""
log "── Stopping all services ──"
systemctl stop opencti-worker@1 opencti-worker@2 opencti-worker@3 2>/dev/null || true
systemctl stop opencti-platform 2>/dev/null || true
systemctl stop rabbitmq 2>/dev/null || true
systemctl stop minio 2>/dev/null || true
systemctl stop redis 2>/dev/null || true

systemctl disable opencti-worker@1 opencti-worker@2 opencti-worker@3 2>/dev/null || true
systemctl disable opencti-platform rabbitmq minio redis 2>/dev/null || true
log "  ✓ All services stopped + disabled"

# ── 2. Remove OpenCTI Platform ───────────────────────────────
log ""
log "── Removing OpenCTI Platform ──"
rm -rf /etc/saids/opencti
rm -rf /var/log/opencti
rm -f /var/lib/.v2_setup_opencti_done
log "  ✓ /etc/saids/opencti removed"

# ── 3. Remove OpenCTI Worker ─────────────────────────────────
log ""
log "── Removing OpenCTI Worker ──"
rm -rf /etc/saids/opencti-worker
rm -rf /var/log/opencti-worker
rm -f /var/lib/.v2_setup_opencti_worker_done
log "  ✓ /etc/saids/opencti-worker removed"

# ── 4. Remove RabbitMQ ───────────────────────────────────────
log ""
log "── Removing RabbitMQ ──"
rm -rf /opt/rabbitmq
if [[ "${KEEP_DATA:-false}" != "true" ]]; then
    rm -rf /var/lib/rabbitmq
fi
rm -rf /var/log/rabbitmq
rm -rf /etc/rabbitmq
rm -f /var/lib/.v2_rabbitmq_setup_done
log "  ✓ RabbitMQ removed"

# ── 5. Remove MinIO ──────────────────────────────────────────
log ""
log "── Removing MinIO ──"
if [[ "${KEEP_DATA:-false}" != "true" ]]; then
    rm -rf /var/lib/minio
fi
rm -rf /var/log/minio
rm -rf /etc/minio
rm -f /var/lib/minio/.setup_done
log "  ✓ MinIO removed"

# ── 6. Remove systemd units ─────────────────────────────────
log ""
log "── Removing systemd units ──"
rm -f /etc/systemd/system/opencti-platform.service
rm -f /etc/systemd/system/opencti-worker@.service
rm -f /etc/systemd/system/rabbitmq.service
rm -f /etc/systemd/system/minio.service
systemctl daemon-reload
log "  ✓ Service units removed"

# ── 7. Remove scripts from /usr/local/bin/ ───────────────────
log ""
log "── Removing scripts from /usr/local/bin/ ──"
rm -f /usr/local/bin/v2_*.sh
rm -f /usr/local/bin/minio
rm -f /usr/local/bin/mc
log "  ✓ /usr/local/bin/ cleaned"

# ── 8. Remove runtimes ───────────────────────────────────────
log ""
log "── Removing Python 3.12 + Node.js 22 ──"
rm -rf /opt/python312
rm -rf /opt/nodejs
rm -f /etc/ld.so.conf.d/python312.conf
ldconfig 2>/dev/null || true
rm -f /usr/local/bin/python3.12 /usr/local/bin/pip3.12
rm -f /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx
rm -f /usr/bin/node /usr/bin/npm /usr/bin/npx
rm -f /var/lib/.v2_python_installed /var/lib/.v2_nodejs_installed
log "  ✓ Runtimes removed"

# ── 9. Remove configs ────────────────────────────────────────
log ""
log "── Removing config files ──"
rm -f /etc/logrotate.d/opencti
rm -f /etc/redis/redis.conf
rmdir /etc/redis 2>/dev/null || true
log "  ✓ Configs removed"

# ── Done ─────────────────────────────────────────────────────
log ""
log "══════════════════════════════════════════════════════════════"
log "  ✓ UNINSTALL COMPLETE"
log "══════════════════════════════════════════════════════════════"
log ""
log "  Còn lại (không xóa):"
log "    - RPM packages (system deps) — dnf remove nếu cần"
log "    - /etc/saids/ (thư mục rỗng)"
log ""
if [[ "${KEEP_DATA:-false}" == "true" ]]; then
    log "  Data được giữ lại:"
    log "    - /var/lib/rabbitmq/"
    log "    - /var/lib/minio/"
fi

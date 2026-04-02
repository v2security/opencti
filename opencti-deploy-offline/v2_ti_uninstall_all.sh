#!/bin/bash
###############################################################################
# v2_uninstall_cti.sh — Gỡ bỏ hoàn toàn OpenCTI stack
#
# CẢNH BÁO: Script này sẽ XÓA TẤT CẢ — data, config, services, runtimes
# Khi chạy sẽ hỏi riêng:
#   - Có xóa data MinIO không
#   - Có xóa data RabbitMQ không
#   - Có xóa data Redis không
#
# Usage: bash v2_uninstall_cti.sh
###############################################################################
set -euo pipefail

log()   { echo -e "\e[33m[UNINSTALL]\e[0m $1"; }
error() { echo -e "\e[31m[UNINSTALL]\e[0m $1" >&2; exit 1; }

ask_yes_no() {
    local prompt="$1"
    local answer
    while true; do
        read -r -p "$prompt (yes/no): " answer
        case "${answer,,}" in
            yes) return 0 ;;
            no)  return 1 ;;
            *)   echo "Vui lòng nhập yes hoặc no." ;;
        esac
    done
}

[[ $EUID -eq 0 ]] || error "Must run as root"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  CẢNH BÁO: Sẽ gỡ bỏ TOÀN BỘ OpenCTI stack!                 ║"
echo "║                                                            ║"
echo "║  - OpenCTI Platform + Workers                              ║"
echo "║  - MinIO, RabbitMQ, Redis                                  ║"
echo "║  - Python 3.12, Node.js 22                                 ║"
echo "║  - Logs, config, services sẽ bị xóa                        ║"
echo "║  - Data sẽ hỏi xác nhận riêng cho từng dịch vụ            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

read -r -p "Xác nhận gỡ bỏ stack? (yes/no): " CONFIRM
[[ "${CONFIRM,,}" == "yes" ]] || { echo "Hủy."; exit 0; }

if ask_yes_no "Xóa data MinIO tại /var/lib/minio/data"; then
    DELETE_MINIO_DATA=true
else
    DELETE_MINIO_DATA=false
fi

if ask_yes_no "Xóa data RabbitMQ tại /var/lib/rabbitmq"; then
    DELETE_RABBITMQ_DATA=true
else
    DELETE_RABBITMQ_DATA=false
fi

if ask_yes_no "Xóa data Redis tại /var/lib/redis"; then
    DELETE_REDIS_DATA=true
else
    DELETE_REDIS_DATA=false
fi

log "══════════════════════════════════════════════════════════════"
log "  Uninstalling OpenCTI Stack"
log "══════════════════════════════════════════════════════════════"
log "  DELETE_MINIO_DATA=${DELETE_MINIO_DATA}"
log "  DELETE_RABBITMQ_DATA=${DELETE_RABBITMQ_DATA}"
log "  DELETE_REDIS_DATA=${DELETE_REDIS_DATA}"

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
if [[ "${DELETE_RABBITMQ_DATA}" == "true" ]]; then
    rm -rf /var/lib/rabbitmq
    log "  ✓ RabbitMQ data removed"
else
    log "  • RabbitMQ data kept: /var/lib/rabbitmq"
fi
rm -rf /var/log/rabbitmq
rm -rf /etc/rabbitmq
rm -f /var/lib/.v2_rabbitmq_setup_done
log "  ✓ RabbitMQ removed"

# ── 5. Remove MinIO ──────────────────────────────────────────
log ""
log "── Removing MinIO ──"
if [[ "${DELETE_MINIO_DATA}" == "true" ]]; then
    rm -rf /var/lib/minio
    log "  ✓ MinIO data removed"
else
    log "  • MinIO data kept: /var/lib/minio/data"
fi
rm -rf /var/log/minio
rm -rf /etc/minio
rm -f /var/lib/minio/.setup_done
log "  ✓ MinIO removed"

# ── 6. Remove Redis ──────────────────────────────────────────
log ""
log "── Removing Redis data/config ──"
if [[ "${DELETE_REDIS_DATA}" == "true" ]]; then
    rm -rf /var/lib/redis
    log "  ✓ Redis data removed"
else
    log "  • Redis data kept: /var/lib/redis"
fi

# ── 7. Remove systemd units ──────────────────────────────────
log ""
log "── Removing systemd units ──"
rm -f /etc/systemd/system/opencti-platform.service
rm -f /etc/systemd/system/opencti-worker@.service
rm -f /etc/systemd/system/rabbitmq.service
rm -f /etc/systemd/system/minio.service
systemctl daemon-reload
log "  ✓ Service units removed"

# ── 8. Remove scripts from /usr/local/bin/ ───────────────────
log ""
log "── Removing scripts from /usr/local/bin/ ──"
rm -f /usr/local/bin/v2_*.sh
rm -f /usr/local/bin/minio
rm -f /usr/local/bin/mc
log "  ✓ /usr/local/bin/ cleaned"

# ── 9. Remove runtimes ───────────────────────────────────────
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

# ── 10. Remove configs ───────────────────────────────────────
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
if [[ "${DELETE_RABBITMQ_DATA}" != "true" ]]; then
    log "  Data RabbitMQ được giữ lại: /var/lib/rabbitmq/"
fi
if [[ "${DELETE_MINIO_DATA}" != "true" ]]; then
    log "  Data MinIO được giữ lại: /var/lib/minio/data/"
fi
if [[ "${DELETE_REDIS_DATA}" != "true" ]]; then
    log "  Data Redis được giữ lại: /var/lib/redis/"
fi
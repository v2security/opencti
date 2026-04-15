#!/bin/bash
###############################################################################
# v2_uninstall_opencti_infra.sh — Gỡ bỏ INFRA (Redis, MinIO, RabbitMQ, runtimes)
#
# CẢNH BÁO: Xóa infra services, config, runtimes.
# Hỏi xác nhận riêng cho data mỗi service.
# KHÔNG đụng OpenCTI Platform/Worker — dùng v2_uninstall_opencti_app.sh.
#
# Usage: v2_uninstall_opencti_infra.sh
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
echo "║  CẢNH BÁO: Sẽ gỡ bỏ INFRA!                                 ║"
echo "║                                                            ║"
echo "║  - MinIO, RabbitMQ, Redis                                  ║"
echo "║  - Python 3.12, Node.js 22                                 ║"
echo "║  - Config, systemd units (infra)                           ║"
echo "║  - Data sẽ hỏi xác nhận riêng cho từng dịch vụ             ║"
echo "║                                                            ║"
echo "║  KHÔNG đụng: OpenCTI Platform, Workers                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

read -r -p "Xác nhận gỡ bỏ infra? (yes/no): " CONFIRM
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
log "  Uninstalling INFRA"
log "══════════════════════════════════════════════════════════════"

# ── 1. Stop infra services ───────────────────────────────────
log ""
log "── Stopping infra services ──"
systemctl stop rabbitmq 2>/dev/null || true
systemctl stop minio 2>/dev/null || true
systemctl stop redis 2>/dev/null || true
systemctl disable rabbitmq minio redis 2>/dev/null || true
log "  ✓ Infra services stopped + disabled"

# ── 2. Remove RabbitMQ ───────────────────────────────────────
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

# ── 3. Remove MinIO ──────────────────────────────────────────
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
rm -f /usr/local/bin/minio /usr/local/bin/mc
log "  ✓ MinIO removed"

# ── 4. Remove Redis ──────────────────────────────────────────
log ""
log "── Removing Redis ──"
if [[ "${DELETE_REDIS_DATA}" == "true" ]]; then
    rm -rf /var/lib/redis
    log "  ✓ Redis data removed"
else
    log "  • Redis data kept: /var/lib/redis"
fi
rm -f /etc/redis/redis.conf
rmdir /etc/redis 2>/dev/null || true
rm -rf /etc/systemd/system/redis.service.d
log "  ✓ Redis removed"

# ── 5. Remove infra systemd units ────────────────────────────
log ""
log "── Removing infra systemd units ──"
rm -f /etc/systemd/system/rabbitmq.service
rm -f /etc/systemd/system/minio.service
rm -f /etc/systemd/system/disable-thp.service
systemctl daemon-reload
log "  ✓ Infra service units removed"

# ── 6. Remove infra scripts from /usr/local/bin/ ─────────────
log ""
log "── Removing infra scripts from /usr/local/bin/ ──"
rm -f /usr/local/bin/v2_setup_minio.sh /usr/local/bin/v2_start_minio.sh
rm -f /usr/local/bin/v2_stop_minio.sh /usr/local/bin/v2_uninstall_minio.sh
rm -f /usr/local/bin/v2_start_rabbitmq.sh /usr/local/bin/v2_stop_rabbitmq.sh
rm -f /usr/local/bin/v2_uninstall_rabbitmq.sh
rm -f /usr/local/bin/v2_setup_redis.sh
rm -f /usr/local/bin/v2_uninstall_python.sh /usr/local/bin/v2_uninstall_nodejs.sh
rm -f /usr/local/bin/v2_uninstall_opencti_infra.sh
log "  ✓ Infra scripts cleaned"

# ── 7. Remove runtimes ───────────────────────────────────────
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

# ── 8. Remove configs ────────────────────────────────────────
log ""
log "── Removing infra config files ──"
rm -f /etc/logrotate.d/opencti
rm -f /etc/sysctl.d/99-redis.conf
log "  ✓ Configs removed"

# ── Done ─────────────────────────────────────────────────────
log ""
log "══════════════════════════════════════════════════════════════"
log "  ✓ INFRA UNINSTALL COMPLETE"
log "══════════════════════════════════════════════════════════════"
log ""
log "  Còn lại (không xóa):"
log "    - RPM packages (system deps) — dnf remove nếu cần"
log "    - OpenCTI Platform + Workers (dùng v2_uninstall_opencti_app.sh)"
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

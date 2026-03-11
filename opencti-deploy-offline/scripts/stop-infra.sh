#!/bin/bash
###############################################################################
# STOP INFRA — Dừng và xóa sạch Infrastructure (MinIO + Redis + RabbitMQ)
# Target: Rocky Linux 9
#
# Script này LÀM NGƯỢC lại setup_infra.sh — dừng services, xóa toàn bộ:
#   • Systemd services (redis, minio, rabbitmq-server)
#   • MinIO        → /usr/local/bin/minio, /etc/minio/, /var/lib/minio/, /var/log/minio/
#   • Redis        → dnf remove redis (RPM), /etc/redis/, /var/lib/redis/, /var/log/redis/
#   • RabbitMQ     → /opt/rabbitmq/, /etc/rabbitmq/, /var/lib/rabbitmq/, /var/log/rabbitmq/
#   • Run scripts  → /opt/infra/scripts/
#   • Symlinks: mc, rabbitmq-*
#
# ⚠ KHÔNG xóa RPMs đã cài (gcc, erlang, etc.) — vì có thể hệ thống cần
#
# Cách dùng:
#   bash stop-infra.sh           # Xác nhận trước khi xóa
#   bash stop-infra.sh --force   # Xóa không hỏi
#
###############################################################################
set -euo pipefail

# ── Helpers ──────────────────────────────────────────────────
info()   { echo "  → $*"; }
ok()     { echo "  ✓ $*"; }
warn()   { echo "  ⚠ $*"; }

FORCE=false
for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE=true ;;
    esac
done

[[ $EUID -eq 0 ]] || { echo "  ✗ Cần chạy với quyền root" >&2; exit 1; }

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║   STOP INFRA — Xóa sạch MinIO + Redis + RabbitMQ          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  Sẽ XÓA toàn bộ:"
echo "    • Services:  redis, minio, rabbitmq-server"
echo "    • MinIO:     /usr/local/bin/minio, /etc/minio/, /var/lib/minio/, /var/log/minio/"
echo "    • Redis:     RPM remove, /etc/redis/, /var/lib/redis/, /var/log/redis/"
echo "    • RabbitMQ:  /opt/rabbitmq/, /etc/rabbitmq/, /var/lib/rabbitmq/, /var/log/rabbitmq/"
echo "    • Scripts:   /opt/infra/scripts/"
echo "    • Symlinks:  mc, rabbitmq-*"
echo ""
echo "  KHÔNG xóa: RPMs đã cài (gcc, erlang, make, etc.)"
echo ""

if [[ "$FORCE" != "true" ]]; then
    read -rp "  ⚠ Bạn có chắc chắn muốn XÓA TẤT CẢ? (y/N): " answer
    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
        echo "  → Hủy bỏ."
        exit 0
    fi
fi

echo ""

# ══════════════════════════════════════════════════════════════
# 1. Stop & disable services
# ══════════════════════════════════════════════════════════════
info "Stopping services..."

for svc in rabbitmq-server minio redis; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
done
ok "Services stopped"

# ══════════════════════════════════════════════════════════════
# 2. Remove systemd unit files
# ══════════════════════════════════════════════════════════════
info "Removing systemd units..."

rm -f /etc/systemd/system/minio.service
rm -f /etc/systemd/system/rabbitmq-server.service
# redis.service is managed by RPM — removed with dnf remove redis
systemctl daemon-reload
ok "Systemd units removed"

# ══════════════════════════════════════════════════════════════
# 3. Remove MinIO
# ══════════════════════════════════════════════════════════════
info "Removing MinIO..."

rm -f /usr/local/bin/minio
rm -f /usr/local/bin/mc
rm -rf /etc/minio
rm -rf /var/lib/minio
rm -rf /var/log/minio
ok "MinIO removed"

# ══════════════════════════════════════════════════════════════
# 4. Remove Redis
# ══════════════════════════════════════════════════════════════
info "Removing Redis..."

# Redis installed via RPM — remove package + data
dnf remove -y redis 2>/dev/null || rpm -e redis 2>/dev/null || true
rm -rf /etc/redis
rm -rf /var/lib/redis
rm -rf /var/log/redis
ok "Redis removed (RPM + data)"

# ══════════════════════════════════════════════════════════════
# 5. Remove RabbitMQ
# ══════════════════════════════════════════════════════════════
info "Removing RabbitMQ..."

rm -rf /opt/rabbitmq
rm -rf /etc/rabbitmq
rm -rf /var/lib/rabbitmq
rm -rf /var/log/rabbitmq
# Remove all rabbitmq symlinks in /usr/local/bin/
rm -f /usr/local/bin/rabbitmq-server
rm -f /usr/local/bin/rabbitmqctl
rm -f /usr/local/bin/rabbitmq-plugins
rm -f /usr/local/bin/rabbitmq-diagnostics
rm -f /usr/local/bin/rabbitmq-env
rm -f /usr/local/bin/rabbitmq-defaults
rm -f /usr/local/bin/rabbitmq-queues
rm -f /usr/local/bin/rabbitmq-streams
rm -f /usr/local/bin/rabbitmq-upgrade
ok "RabbitMQ removed"

# ══════════════════════════════════════════════════════════════
# 6. Remove run scripts
# ══════════════════════════════════════════════════════════════
info "Removing run scripts..."

rm -rf /opt/infra
# run_redis.sh not used — Redis uses RPM systemd unit
ok "Run scripts removed"

# ══════════════════════════════════════════════════════════════
# DONE
# ══════════════════════════════════════════════════════════════
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║   ✓ INFRA CLEANUP COMPLETE — Máy đã sạch                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  💡 RPMs (erlang, redis...) vẫn còn."
echo "     Nếu muốn xóa luôn: dnf remove erlang redis"
echo ""

#!/bin/bash
###############################################################################
# STOP APP — Dừng và xóa sạch OpenCTI Platform + Worker
# Target: Rocky Linux 9
#
# Script này LÀM NGƯỢC lại setup_app.sh — dừng services, xóa toàn bộ:
#   • Systemd services (opencti-platform, opencti-worker@{1..N})
#   • OpenCTI Platform   → /etc/saids/application/opencti/
#   • OpenCTI Worker     → /etc/saids/application/opencti-worker/
#   • Python 3.12        → /opt/python312/
#   • Node.js 22         → /opt/nodejs/
#   • Logs               → /var/log/application/opencti{,-worker}/
#   • SSL certs, sysctl, logrotate configs
#   • Symlinks: /usr/bin/{node,npm,npx}
#
# Cách dùng:
#   bash stop-app.sh           # Xác nhận trước khi xóa
#   bash stop-app.sh --force   # Xóa không hỏi
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
echo "║   STOP APP — Xóa sạch OpenCTI Platform + Worker           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  Sẽ XÓA toàn bộ:"
echo "    • Services:  opencti-platform, opencti-worker@{1..3}"
echo "    • Platform:  /etc/saids/application/opencti/"
echo "    • Worker:    /etc/saids/application/opencti-worker/"
echo "    • Python:    /opt/python312/"
echo "    • Node.js:   /opt/nodejs/"
echo "    • Logs:      /var/log/application/opencti{,-worker}/"
echo "    • Configs:   sysctl, logrotate, systemd units"
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

# Workers (stop all instances)
for i in 1 2 3 4 5; do
    systemctl stop "opencti-worker@${i}" 2>/dev/null || true
    systemctl disable "opencti-worker@${i}" 2>/dev/null || true
done

systemctl stop opencti-platform 2>/dev/null || true
systemctl disable opencti-platform 2>/dev/null || true

ok "Services stopped"

# ══════════════════════════════════════════════════════════════
# 2. Remove systemd unit files
# ══════════════════════════════════════════════════════════════
info "Removing systemd units..."

rm -f /etc/systemd/system/opencti-platform.service
rm -f /etc/systemd/system/opencti-worker@.service
systemctl daemon-reload
ok "Systemd units removed"

# ══════════════════════════════════════════════════════════════
# 3. Remove application directories
# ══════════════════════════════════════════════════════════════
info "Removing application directories..."

rm -rf /etc/saids/application/opencti
rm -rf /etc/saids/application/opencti-worker
# Xóa parent nếu trống
rmdir /etc/saids/application 2>/dev/null || true
rmdir /etc/saids 2>/dev/null || true
ok "Application directories removed"

# ══════════════════════════════════════════════════════════════
# 4. Remove runtimes
# ══════════════════════════════════════════════════════════════
info "Removing runtimes..."

rm -rf /opt/python312
rm -rf /opt/nodejs
rm -f /usr/bin/node /usr/bin/npm /usr/bin/npx
ok "Python 3.12 + Node.js 22 removed"

# ══════════════════════════════════════════════════════════════
# 5. Remove logs
# ══════════════════════════════════════════════════════════════
info "Removing logs..."

rm -rf /var/log/application/opencti
rm -rf /var/log/application/opencti-worker
rmdir /var/log/application 2>/dev/null || true
ok "Logs removed"

# ══════════════════════════════════════════════════════════════
# 6. Remove config files
# ══════════════════════════════════════════════════════════════
info "Removing config files..."

rm -f /etc/sysctl.d/90-opencti.conf
rm -f /etc/logrotate.d/opencti
sysctl --system &>/dev/null || true
ok "Sysctl + logrotate configs removed"

# ══════════════════════════════════════════════════════════════
# DONE
# ══════════════════════════════════════════════════════════════
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║   ✓ APP CLEANUP COMPLETE — Máy đã sạch                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

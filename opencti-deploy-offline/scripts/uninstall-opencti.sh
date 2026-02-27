#!/bin/bash
# =============================================================================
# GỠ CÀI ĐẶT OPENCTI + Infrastructure
# Usage: bash uninstall-opencti.sh [--keep-data]
# =============================================================================
set -e

WORKERS=3
KEEP_DATA=false
[[ "${1:-}" == "--keep-data" ]] && KEEP_DATA=true

[[ $EUID -eq 0 ]] || { echo "✗ Cần root"; exit 1; }

echo ""
echo "══════════════════════════════════════════"
echo "  GỠ CÀI ĐẶT OPENCTI [keep-data=$KEEP_DATA]"
echo "══════════════════════════════════════════"
if [[ -t 0 ]]; then
  read -p "  Xác nhận? [y/N] " c
  [[ "$c" =~ ^[yY]$ ]] || exit 0
fi

# Stop services
echo "▸ Stop services"
for i in $(seq 1 $WORKERS); do
  systemctl stop "opencti-worker@$i" 2>/dev/null || true
  systemctl disable "opencti-worker@$i" 2>/dev/null || true
done
for svc in opencti minio rabbitmq-server redis elasticsearch; do
  systemctl stop "$svc" 2>/dev/null || true
  systemctl disable "$svc" 2>/dev/null || true
done

# Systemd units
echo "▸ Xóa systemd units"
rm -f /etc/systemd/system/{opencti,opencti-worker@,elasticsearch,rabbitmq-server,minio}.service
systemctl daemon-reload

# Binaries
echo "▸ Xóa binaries"
rm -rf /opt/opencti-worker /opt/rabbitmq /opt/minio /opt/python312
[[ "$KEEP_DATA" == true ]] || rm -rf /opt/opencti /opt/elasticsearch

# RabbitMQ symlinks
echo "▸ Xóa symlinks"
for bin in /usr/local/bin/rabbitmq*; do
  rm -f "$bin" 2>/dev/null || true
done
rm -f /usr/local/bin/python3.12 /usr/local/bin/python3 /usr/local/bin/pip3
rm -f /tmp/mc

# Configs
echo "▸ Xóa configs"
rm -f /etc/default/minio
rm -rf /etc/rabbitmq

# Data
if [[ "$KEEP_DATA" == false ]]; then
  echo "▸ Xóa data"
  rm -rf /var/lib/rabbitmq /var/log/rabbitmq /var/minio/data
fi

echo ""
echo "  ✓ Gỡ cài đặt hoàn tất"
echo ""

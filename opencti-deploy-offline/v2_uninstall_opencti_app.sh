#!/bin/bash
###############################################################################
# v2_uninstall_opencti_app.sh — Gỡ bỏ APP (OpenCTI Platform + Workers)
#
# CẢNH BÁO: Xóa OpenCTI Platform, Workers, logs.
# KHÔNG đụng infra (Redis, MinIO, RabbitMQ, runtimes) —
# dùng v2_uninstall_opencti_infra.sh.
#
# Usage: v2_uninstall_opencti_app.sh
###############################################################################
set -euo pipefail

log()   { echo -e "\e[33m[UNINSTALL]\e[0m $1"; }
error() { echo -e "\e[31m[UNINSTALL]\e[0m $1" >&2; exit 1; }

[[ $EUID -eq 0 ]] || error "Must run as root"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  CẢNH BÁO: Sẽ gỡ bỏ OpenCTI APP!                           ║"
echo "║                                                            ║"
echo "║  - OpenCTI Platform (/etc/saids/opencti)                   ║"
echo "║  - OpenCTI Workers  (/etc/saids/opencti-worker)            ║"
echo "║  - Logs, setup markers, systemd units (app)                ║"
echo "║                                                            ║"
echo "║  KHÔNG đụng: Redis, MinIO, RabbitMQ, runtimes              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

read -r -p "Xác nhận gỡ bỏ OpenCTI app? (yes/no): " CONFIRM
[[ "${CONFIRM,,}" == "yes" ]] || { echo "Hủy."; exit 0; }

log "══════════════════════════════════════════════════════════════"
log "  Uninstalling OpenCTI APP"
log "══════════════════════════════════════════════════════════════"

# ── 1. Stop app services ─────────────────────────────────────
log ""
log "── Stopping app services ──"
systemctl stop opencti 2>/dev/null || true
systemctl stop opencti-worker@{1..8} 2>/dev/null || true
systemctl disable opencti 2>/dev/null || true
systemctl disable opencti-worker@{1..8} 2>/dev/null || true
log "  ✓ App services stopped + disabled"

# ── 2. Remove Platform ───────────────────────────────────────
log ""
log "── Removing OpenCTI Platform ──"
rm -rf /etc/saids/opencti
rm -rf /var/log/opencti
rm -f /var/lib/.v2_opencti_setup_done
log "  ✓ Platform removed"

# ── 3. Remove Workers ────────────────────────────────────────
log ""
log "── Removing OpenCTI Workers ──"
rm -rf /etc/saids/opencti-worker
rm -rf /var/log/opencti-worker
rm -f /var/lib/.v2_opencti_worker_setup_done
log "  ✓ Workers removed"

# ── 4. Remove app systemd units ──────────────────────────────
log ""
log "── Removing app systemd units ──"
rm -f /etc/systemd/system/opencti.service
rm -f /etc/systemd/system/opencti-worker@.service
systemctl daemon-reload
log "  ✓ App service units removed"

# ── 5. Remove app scripts from /usr/local/bin/ ───────────────
log ""
log "── Removing app scripts from /usr/local/bin/ ──"
rm -f /usr/local/bin/v2_setup_opencti.sh
rm -f /usr/local/bin/v2_setup_opencti_worker.sh
rm -f /usr/local/bin/v2_uninstall_opencti_app.sh
log "  ✓ App scripts cleaned"

# ── Done ─────────────────────────────────────────────────────
log ""
log "══════════════════════════════════════════════════════════════"
log "  ✓ APP UNINSTALL COMPLETE"
log "══════════════════════════════════════════════════════════════"
log ""
log "  Còn lại (không xóa):"
log "    - Infra (Redis, MinIO, RabbitMQ, runtimes)"
log "    - Dùng v2_uninstall_opencti_infra.sh để gỡ infra"
log ""

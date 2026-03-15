#!/bin/bash
###############################################################################
# v2_uninstall_opencti_worker.sh — Completely remove OpenCTI Worker
#
# WARNING: This script will:
#   - Stop and disable opencti-worker@* services
#   - Remove /etc/saids/opencti-worker
#   - Remove logs, systemd service, and scripts from /usr/local/bin
#   - Remove marker file
#
# Usage: ./v2_uninstall_opencti_worker.sh
###############################################################################
set -euo pipefail

WORKER_DIR="/etc/saids/opencti-worker"
MARKER_FILE="/var/lib/.v2_setup_opencti_worker_done"

log()   { echo -e "\e[33m[UNINSTALL-WORKER]\e[0m $1"; }
error() { echo -e "\e[31m[UNINSTALL-WORKER]\e[0m $1" >&2; exit 1; }

[[ $EUID -eq 0 ]] || error "Must run as root"

log "══════════════════════════════════════════════════════════════"
log "  UNINSTALLING OpenCTI Worker"
log "══════════════════════════════════════════════════════════════"

# ── Stop service ─────────────────────────────────────────────
log "Stopping opencti-worker services..."
systemctl stop opencti-worker@1.service 2>/dev/null || true
systemctl disable opencti-worker@1.service 2>/dev/null || true

# ── Remove systemd service ───────────────────────────────────
log "Removing systemd service..."
rm -f /etc/systemd/system/opencti-worker@.service
systemctl daemon-reload

# ── Remove scripts from /usr/local/bin ────────────────────────
log "Removing scripts from /usr/local/bin..."
rm -f /usr/local/bin/v2_start_opencti_worker.sh
rm -f /usr/local/bin/v2_stop_opencti_worker.sh

# ── Remove installation directory ────────────────────────────
log "Removing $WORKER_DIR..."
rm -rf "$WORKER_DIR"

# ── Remove logs ──────────────────────────────────────────────
log "Removing logs..."
rm -rf /var/log/opencti-worker

# ── Remove marker file ───────────────────────────────────────
rm -f "$MARKER_FILE"

log "══════════════════════════════════════════════════════════════"
log "  ✓ OpenCTI Worker UNINSTALL COMPLETE"
log "══════════════════════════════════════════════════════════════"
log ""
log "  Removed:"
log "    - $WORKER_DIR"
log "    - /var/log/opencti-worker"
log "    - opencti-worker@.service"
log "    - /usr/local/bin/v2_start_opencti_worker.sh"
log "    - /usr/local/bin/v2_stop_opencti_worker.sh"
log ""
log "  To reinstall: /etc/saids/opencti-worker/v2_setup_opencti_worker.sh"

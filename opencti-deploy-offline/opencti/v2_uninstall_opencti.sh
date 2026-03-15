#!/bin/bash
###############################################################################
# v2_uninstall_opencti.sh — Completely remove OpenCTI Platform
#
# WARNING: This script will:
#   - Stop and disable opencti-platform service
#   - Remove /etc/saids/opencti
#   - Remove logs, systemd service, and scripts from /usr/local/bin
#   - Remove marker file
#
# Usage: ./v2_uninstall_opencti.sh
###############################################################################
set -euo pipefail

PLATFORM_DIR="/etc/saids/opencti"
MARKER_FILE="/var/lib/.v2_setup_opencti_done"

log()   { echo -e "\e[33m[UNINSTALL-PLATFORM]\e[0m $1"; }
error() { echo -e "\e[31m[UNINSTALL-PLATFORM]\e[0m $1" >&2; exit 1; }

[[ $EUID -eq 0 ]] || error "Must run as root"

log "══════════════════════════════════════════════════════════════"
log "  UNINSTALLING OpenCTI Platform"
log "══════════════════════════════════════════════════════════════"

# ── Stop service ─────────────────────────────────────────────
log "Stopping opencti-platform service..."
systemctl stop opencti-platform.service 2>/dev/null || true
systemctl disable opencti-platform.service 2>/dev/null || true

# ── Remove systemd service ───────────────────────────────────
log "Removing systemd service..."
rm -f /etc/systemd/system/opencti-platform.service
systemctl daemon-reload

# ── Remove scripts from /usr/local/bin ────────────────────────
log "Removing scripts from /usr/local/bin..."
rm -f /usr/local/bin/v2_start_opencti.sh
rm -f /usr/local/bin/v2_stop_opencti.sh

# ── Remove installation directory ────────────────────────────
log "Removing $PLATFORM_DIR..."
rm -rf "$PLATFORM_DIR"

# ── Remove logs ──────────────────────────────────────────────
log "Removing logs..."
rm -rf /var/log/opencti

# ── Remove marker file ───────────────────────────────────────
rm -f "$MARKER_FILE"

log "══════════════════════════════════════════════════════════════"
log "  ✓ OpenCTI Platform UNINSTALL COMPLETE"
log "══════════════════════════════════════════════════════════════"
log ""
log "  Removed:"
log "    - $PLATFORM_DIR"
log "    - /var/log/opencti"
log "    - opencti-platform.service"
log "    - /usr/local/bin/v2_start_opencti.sh"
log "    - /usr/local/bin/v2_stop_opencti.sh"
log ""
log "  To reinstall: /etc/saids/opencti/v2_setup_opencti.sh"

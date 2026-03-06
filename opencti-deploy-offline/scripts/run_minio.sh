#!/bin/bash
###############################################################################
# MinIO Run Script — Called by systemd (minio.service)
#
# Binary:  /opt/minio/bin/minio
# Data:    /var/lib/minio/data
# Config:  /etc/minio/minio.conf        (MOUNT từ ngoài vào, KHÔNG auto-generate)
# Logs:    /var/log/minio/ (via systemd StandardOutput=append:)
#
# Biến trong config phải khớp với start.sh:
#   MINIO__ACCESS_KEY  → MINIO_ROOT_USER
#   MINIO__SECRET_KEY  → MINIO_ROOT_PASSWORD
###############################################################################
set -euo pipefail

MINIO_BIN="/opt/minio/bin/minio"
MINIO_DATA="/var/lib/minio/data"
MINIO_CONFIG="/etc/minio/minio.conf"

# ── Validate config (phải được mount từ ngoài vào) ──────────
[[ -f "$MINIO_CONFIG" ]] || {
    echo "ERROR: MinIO config not found at $MINIO_CONFIG"
    echo "  Config phải được mount/copy từ ngoài vào, KHÔNG auto-generate."
    echo "  Xem: config/minio.conf → /etc/minio/minio.conf"
    exit 1
}

# ── Load config ──────────────────────────────────────────────
set -a
source "$MINIO_CONFIG"
set +a

# ── Validate required variables ──────────────────────────────
[[ -n "${MINIO_ROOT_USER:-}" ]] || { echo "ERROR: MINIO_ROOT_USER not set in $MINIO_CONFIG"; exit 1; }
[[ -n "${MINIO_ROOT_PASSWORD:-}" ]] || { echo "ERROR: MINIO_ROOT_PASSWORD not set in $MINIO_CONFIG"; exit 1; }
MINIO_VOLUMES="${MINIO_VOLUMES:-$MINIO_DATA}"
MINIO_OPTS="${MINIO_OPTS:---console-address :9001}"

# ── Validate binary ─────────────────────────────────────────
[[ -x "$MINIO_BIN" ]] || { echo "ERROR: MinIO binary not found at $MINIO_BIN"; exit 1; }

# ── Ensure directories ──────────────────────────────────────
mkdir -p "$MINIO_DATA" /var/log/minio

# ── Start ────────────────────────────────────────────────────
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting MinIO server..."
echo "  Binary:  $MINIO_BIN"
echo "  Data:    $MINIO_VOLUMES"
echo "  User:    $MINIO_ROOT_USER"
echo "  Config:  $MINIO_CONFIG (mounted)"
echo "  Logs:    /var/log/minio/"
echo "  API:     :9000"
echo "  Console: :9001"

exec "$MINIO_BIN" server $MINIO_VOLUMES $MINIO_OPTS

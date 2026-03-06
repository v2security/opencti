#!/bin/bash
###############################################################################
# Redis Run Script — Called by systemd (redis.service)
#
# Binary:  /opt/redis/bin/redis-server  (compiled from files/redis-*.tar.gz)
#          Fallback: /usr/bin/redis-server (RPM)
# Config:  /etc/redis/redis.conf        (MOUNT từ ngoài vào, KHÔNG auto-generate)
# Data:    /var/lib/redis
# Logs:    /var/log/redis/redis.log      (via redis.conf logfile directive)
#
# Biến trong config phải khớp với start.sh:
#   REDIS__PORT      → port
#   REDIS__PASSWORD  → requirepass
###############################################################################
set -euo pipefail

REDIS_BIN="/opt/redis/bin/redis-server"
REDIS_CONF="/etc/redis/redis.conf"
REDIS_DATA="/var/lib/redis"
REDIS_LOG_DIR="/var/log/redis"

# ── Find redis-server binary ────────────────────────────────
if [[ ! -x "$REDIS_BIN" ]]; then
    REDIS_BIN=$(command -v redis-server 2>/dev/null || echo "/usr/bin/redis-server")
fi
[[ -x "$REDIS_BIN" ]] || { echo "ERROR: redis-server not found"; exit 1; }

# ── Validate config (phải được mount từ ngoài vào) ──────────
[[ -f "$REDIS_CONF" ]] || {
    echo "ERROR: Redis config not found at $REDIS_CONF"
    echo "  Config phải được mount/copy từ ngoài vào, KHÔNG auto-generate."
    echo "  Xem: config/redis.conf → /etc/redis/redis.conf"
    exit 1
}

# ── Ensure directories ──────────────────────────────────────
mkdir -p "$REDIS_DATA" "$REDIS_LOG_DIR"

# ── Start ────────────────────────────────────────────────────
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Redis server..."
echo "  Binary:  $REDIS_BIN"
echo "  Version: $($REDIS_BIN --version 2>/dev/null || echo 'unknown')"
echo "  Config:  $REDIS_CONF (mounted)"
echo "  Data:    $REDIS_DATA"
echo "  Logs:    $REDIS_LOG_DIR/redis.log"

exec "$REDIS_BIN" "$REDIS_CONF"

#!/bin/bash
###############################################################################
# RabbitMQ Run Script — Called by systemd (rabbitmq-server.service)
#
# Binary:  /opt/rabbitmq/sbin/rabbitmq-server
# Data:    /var/lib/rabbitmq/mnesia
# Logs:    /var/log/rabbitmq/
# Config:  /etc/rabbitmq/rabbitmq.conf      (MOUNT từ ngoài vào, KHÔNG auto-generate)
#          /etc/rabbitmq/rabbitmq-env.conf   (MOUNT từ ngoài vào)
#
# Biến trong config phải khớp với start.sh:
#   RABBITMQ__PORT             → listeners.tcp.default (5672)
#   RABBITMQ__PORT_MANAGEMENT  → management.tcp.port (15672)
#   RABBITMQ__USERNAME         → user (tạo bởi setup_infra.sh)
#   RABBITMQ__PASSWORD         → password (tạo bởi setup_infra.sh)
###############################################################################
set -euo pipefail

RABBITMQ_SBIN="/opt/rabbitmq/sbin"

# ── Environment ──────────────────────────────────────────────
export RABBITMQ_BASE="/opt/rabbitmq"
export RABBITMQ_LOG_BASE="/var/log/rabbitmq"
export RABBITMQ_MNESIA_BASE="/var/lib/rabbitmq/mnesia"
export RABBITMQ_ENABLED_PLUGINS_FILE="/opt/rabbitmq/etc/rabbitmq/enabled_plugins"
export HOME="/root"

# ── Validate config (phải được mount từ ngoài vào) ──────────
[[ -f /etc/rabbitmq/rabbitmq.conf ]] || {
    echo "ERROR: RabbitMQ config not found at /etc/rabbitmq/rabbitmq.conf"
    echo "  Config phải được mount/copy từ ngoài vào, KHÔNG auto-generate."
    echo "  Xem: config/rabbitmq.conf → /etc/rabbitmq/rabbitmq.conf"
    exit 1
}
export RABBITMQ_CONFIG_FILE="/etc/rabbitmq/rabbitmq"

# ── Load env config if mounted ───────────────────────────────
if [[ -f /etc/rabbitmq/rabbitmq-env.conf ]]; then
    export RABBITMQ_CONF_ENV_FILE="/etc/rabbitmq/rabbitmq-env.conf"
fi

# ── Validate binary ─────────────────────────────────────────
[[ -x "$RABBITMQ_SBIN/rabbitmq-server" ]] || {
    echo "ERROR: rabbitmq-server not found at $RABBITMQ_SBIN/rabbitmq-server"
    exit 1
}

# ── Ensure directories ──────────────────────────────────────
mkdir -p "$RABBITMQ_LOG_BASE" "$RABBITMQ_MNESIA_BASE"

# ── Start ────────────────────────────────────────────────────
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting RabbitMQ server..."
echo "  Base:    $RABBITMQ_BASE"
echo "  Data:    $RABBITMQ_MNESIA_BASE"
echo "  Logs:    $RABBITMQ_LOG_BASE"
echo "  Config:  /etc/rabbitmq/rabbitmq.conf (mounted)"
echo "  EnvConf: ${RABBITMQ_CONF_ENV_FILE:-none}"
echo "  Plugins: $RABBITMQ_ENABLED_PLUGINS_FILE"

exec "$RABBITMQ_SBIN/rabbitmq-server"

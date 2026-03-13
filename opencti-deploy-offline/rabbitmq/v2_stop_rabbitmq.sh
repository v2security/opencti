#!/bin/bash
#===============================================================================
# v2_stop_rabbitmq.sh - RabbitMQ Stop Script (gọi bởi systemd ExecStop)
#===============================================================================
#
# MÔ TẢ:
#   Script dừng RabbitMQ server gracefully. Được gọi bởi systemd khi stop.
#   Sử dụng rabbitmqctl stop để graceful shutdown.
#
# INPUT:
#   Installation:
#     - /opt/rabbitmq/sbin/rabbitmqctl : RabbitMQ control binary
#
#   Config:
#     - /etc/rabbitmq/rabbitmq-env.conf : Environment config
#
# OUTPUT:
#   Process:
#     - RabbitMQ server stopped
#
# USAGE:
#   # Gọi bởi systemd (ExecStop)
#   ExecStop=/usr/local/bin/v2_stop_rabbitmq.sh
#
#   # Chạy thủ công
#   bash /usr/local/bin/v2_stop_rabbitmq.sh
#
# FLOW:
#   1. Thử rabbitmqctl stop (graceful)
#   2. Nếu fail, tìm và kill process
#
#===============================================================================

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
INSTALL_DIR="/opt/rabbitmq"
CONFIG_DIR="/etc/rabbitmq"
DATA_DIR="/var/lib/rabbitmq"
TIMEOUT=30

#-------------------------------------------------------------------------------
# Load environment config
#-------------------------------------------------------------------------------
if [[ -f "${CONFIG_DIR}/rabbitmq-env.conf" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_DIR}/rabbitmq-env.conf"
fi

export RABBITMQ_NODENAME="${RABBITMQ_NODENAME:-rabbit@localhost}"
export HOME="${DATA_DIR}"

#-------------------------------------------------------------------------------
# Log function
#-------------------------------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

#-------------------------------------------------------------------------------
# Stop RabbitMQ gracefully
#-------------------------------------------------------------------------------
log "Stopping RabbitMQ server..."

RABBITMQCTL="${INSTALL_DIR}/sbin/rabbitmqctl"

# Try graceful stop with rabbitmqctl
if [[ -x "${RABBITMQCTL}" ]]; then
    log "Using rabbitmqctl stop..."
    if "${RABBITMQCTL}" stop 2>/dev/null; then
        log "RabbitMQ stopped gracefully."
        exit 0
    else
        log "rabbitmqctl stop failed, trying alternative method..."
    fi
fi

# Fallback: find and kill processes
log "Finding RabbitMQ processes..."

# Find beam.smp (Erlang VM) processes related to RabbitMQ
RABBIT_PIDS=$(pgrep -f "beam.smp.*rabbit" 2>/dev/null || true)

if [[ -z "${RABBIT_PIDS}" ]]; then
    log "No RabbitMQ process found. Already stopped."
    exit 0
fi

log "Found RabbitMQ processes: ${RABBIT_PIDS}"

# Send SIGTERM
for pid in ${RABBIT_PIDS}; do
    if kill -0 "${pid}" 2>/dev/null; then
        log "Sending SIGTERM to PID ${pid}..."
        kill -TERM "${pid}" 2>/dev/null || true
    fi
done

# Wait for processes to stop
WAIT=${TIMEOUT}
while [[ ${WAIT} -gt 0 ]]; do
    RABBIT_PIDS=$(pgrep -f "beam.smp.*rabbit" 2>/dev/null || true)
    if [[ -z "${RABBIT_PIDS}" ]]; then
        log "RabbitMQ stopped gracefully."
        exit 0
    fi
    log "Waiting for RabbitMQ to stop... (${WAIT}s remaining)"
    sleep 1
    ((WAIT--))
done

# Force kill
RABBIT_PIDS=$(pgrep -f "beam.smp.*rabbit" 2>/dev/null || true)
if [[ -n "${RABBIT_PIDS}" ]]; then
    log "Timeout! Force killing remaining processes..."
    for pid in ${RABBIT_PIDS}; do
        kill -KILL "${pid}" 2>/dev/null || true
    done
    log "RabbitMQ force stopped."
fi

# Also kill epmd if running
EPMD_PID=$(pgrep -f "epmd" 2>/dev/null || true)
if [[ -n "${EPMD_PID}" ]]; then
    log "Stopping epmd (PID: ${EPMD_PID})..."
    kill -TERM "${EPMD_PID}" 2>/dev/null || true
fi

exit 0

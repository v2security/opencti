#!/bin/bash
#===============================================================================
# v2_start_rabbitmq.sh - RabbitMQ Start Script (gọi bởi systemd ExecStart)
#===============================================================================
#
# MÔ TẢ:
#   Script khởi động RabbitMQ server. Được gọi bởi systemd khi start service.
#   Load config và chạy rabbitmq-server.
#
# INPUT:
#   Installation:
#     - /opt/rabbitmq/sbin/rabbitmq-server : RabbitMQ server binary
#
#   Config files:
#     - /etc/rabbitmq/rabbitmq-env.conf : Environment config
#     - /etc/rabbitmq/rabbitmq.conf     : Main config
#
#   Environment variables (từ systemd hoặc config file):
#     - RABBITMQ_USER      : User sở hữu (default: admin)
#     - RABBITMQ_GROUP     : Group sở hữu (default: admin)
#
# OUTPUT:
#   Services:
#     - RabbitMQ AMQP      : port 5672
#     - RabbitMQ Management: port 15672
#
#   Logs:
#     - /var/log/rabbitmq/
#     - stdout/stderr → systemd journal
#
# OWNER:
#   Mặc định: admin:admin (phải khớp với rabbitmq.service)
#
# USAGE:
#   # Gọi bởi systemd (ExecStart)
#   ExecStart=/usr/local/bin/v2_start_rabbitmq.sh
#
#   # Chạy thủ công (debug)
#   RABBITMQ_USER=admin bash /usr/local/bin/v2_start_rabbitmq.sh
#
# LƯU Ý:
#   - Script sử dụng exec để thay thế shell process
#   - RABBITMQ_USER/GROUP phải khớp với v2_setup_rabbitmq.sh và rabbitmq.service
#
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
INSTALL_DIR="/opt/rabbitmq"
CONFIG_DIR="/etc/rabbitmq"
DATA_DIR="/var/lib/rabbitmq"
LOG_DIR="/var/log/rabbitmq"

# Default owner
RABBITMQ_USER="${RABBITMQ_USER:-admin}"
RABBITMQ_GROUP="${RABBITMQ_GROUP:-admin}"

#-------------------------------------------------------------------------------
# Load environment config
#-------------------------------------------------------------------------------
if [[ -f "${CONFIG_DIR}/rabbitmq-env.conf" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_DIR}/rabbitmq-env.conf"
fi

#-------------------------------------------------------------------------------
# Set environment variables
#-------------------------------------------------------------------------------
export RABBITMQ_NODENAME="${RABBITMQ_NODENAME:-rabbit@localhost}"
export RABBITMQ_BASE="${DATA_DIR}"
export RABBITMQ_MNESIA_BASE="${DATA_DIR}/mnesia"
export RABBITMQ_LOG_BASE="${LOG_DIR}"
export RABBITMQ_CONFIG_FILE="${CONFIG_DIR}/rabbitmq"
export RABBITMQ_ENABLED_PLUGINS_FILE="${CONFIG_DIR}/enabled_plugins"
export HOME="${DATA_DIR}"

#-------------------------------------------------------------------------------
# Check binary exists
#-------------------------------------------------------------------------------
RABBITMQ_SERVER="${INSTALL_DIR}/sbin/rabbitmq-server"

if [[ ! -x "${RABBITMQ_SERVER}" ]]; then
    echo "ERROR: rabbitmq-server not found or not executable: ${RABBITMQ_SERVER}" >&2
    exit 1
fi

#-------------------------------------------------------------------------------
# Start RabbitMQ server
#-------------------------------------------------------------------------------
echo "=============================================="
echo "Starting RabbitMQ server..."
echo "=============================================="
echo "  User     : ${RABBITMQ_USER}"
echo "  Node     : ${RABBITMQ_NODENAME}"
echo "  Data     : ${DATA_DIR}"
echo "  Config   : ${CONFIG_DIR}"
echo "  AMQP     : port 5672"
echo "  Management: port 15672"
echo "=============================================="

# Run RabbitMQ server in foreground
exec "${RABBITMQ_SERVER}"

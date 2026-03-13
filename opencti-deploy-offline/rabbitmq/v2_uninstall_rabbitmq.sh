#!/bin/bash
#===============================================================================
# v2_uninstall_rabbitmq.sh - RabbitMQ Complete Uninstall (gỡ bỏ hoàn toàn)
#===============================================================================
#
# MÔ TẢ:
#   Script gỡ bỏ hoàn toàn RabbitMQ: stop service, xóa files, xóa config.
#   CẢNH BÁO: Script này sẽ XÓA TẤT CẢ DATA!
#
# INPUT:
#   Environment variables (tùy chọn):
#     - KEEP_DATA=true     : Giữ lại data directory (default: false)
#     - KEEP_CONFIG=true   : Giữ lại config files (default: false)
#
# OUTPUT:
#   Removed:
#     - RabbitMQ service stopped and disabled
#     - /opt/rabbitmq/        (installation)
#     - /var/lib/rabbitmq/    (data - trừ khi KEEP_DATA=true)
#     - /var/log/rabbitmq/    (logs)
#     - /etc/rabbitmq/        (config - trừ khi KEEP_CONFIG=true)
#     - /etc/systemd/system/rabbitmq.service
#     - Symlinks in /usr/local/bin/
#
# USAGE:
#   # Gỡ hoàn toàn
#   bash v2_uninstall_rabbitmq.sh
#
#   # Giữ lại data
#   KEEP_DATA=true bash v2_uninstall_rabbitmq.sh
#
#   # Giữ lại config
#   KEEP_CONFIG=true bash v2_uninstall_rabbitmq.sh
#
# LƯU Ý:
#   - Script yêu cầu quyền root
#   - Sẽ xóa tất cả data nếu không set KEEP_DATA=true
#
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KEEP_DATA="${KEEP_DATA:-false}"
KEEP_CONFIG="${KEEP_CONFIG:-false}"

INSTALL_DIR="/opt/rabbitmq"
DATA_DIR="/var/lib/rabbitmq"
LOG_DIR="/var/log/rabbitmq"
CONFIG_DIR="/etc/rabbitmq"
SERVICE_FILE="/etc/systemd/system/rabbitmq.service"

#-------------------------------------------------------------------------------
# Info
#-------------------------------------------------------------------------------
echo ""
log_warn "=========================================="
log_warn "       RABBITMQ UNINSTALL                "
log_warn "=========================================="
log_info "  KEEP_DATA=${KEEP_DATA}"
log_info "  KEEP_CONFIG=${KEEP_CONFIG}"
echo ""

#-------------------------------------------------------------------------------
# Stop and disable service
#-------------------------------------------------------------------------------
log_info "Stopping RabbitMQ service..."

if systemctl is-active --quiet rabbitmq 2>/dev/null; then
    systemctl stop rabbitmq || true
fi

if systemctl is-enabled --quiet rabbitmq 2>/dev/null; then
    systemctl disable rabbitmq || true
fi

# Also run stop script directly
if [[ -f "/usr/local/bin/v2_stop_rabbitmq.sh" ]]; then
    bash /usr/local/bin/v2_stop_rabbitmq.sh || true
fi

#-------------------------------------------------------------------------------
# Remove service file
#-------------------------------------------------------------------------------
if [[ -f "${SERVICE_FILE}" ]]; then
    log_info "Removing ${SERVICE_FILE}..."
    rm -f "${SERVICE_FILE}"
    systemctl daemon-reload
fi

#-------------------------------------------------------------------------------
# Remove symlinks
#-------------------------------------------------------------------------------
log_info "Removing symlinks from /usr/local/bin/..."

BINARIES=(
    "rabbitmqctl"
    "rabbitmq-server"
    "rabbitmq-plugins"
    "rabbitmq-diagnostics"
    "rabbitmq-queues"
    "rabbitmq-streams"
    "rabbitmq-upgrade"
)

for bin in "${BINARIES[@]}"; do
    if [[ -L "/usr/local/bin/${bin}" ]]; then
        rm -f "/usr/local/bin/${bin}"
        log_info "  Removed: ${bin}"
    fi
done

#-------------------------------------------------------------------------------
# Remove directories
#-------------------------------------------------------------------------------
# Installation directory (always remove)
if [[ -d "${INSTALL_DIR}" ]]; then
    log_info "Removing installation: ${INSTALL_DIR}..."
    rm -rf "${INSTALL_DIR}"
fi

# Data directory
if [[ "${KEEP_DATA}" != "true" ]]; then
    if [[ -d "${DATA_DIR}" ]]; then
        log_warn "Deleting data directory: ${DATA_DIR}..."
        rm -rf "${DATA_DIR}"
    fi
else
    log_info "Keeping data directory: ${DATA_DIR}"
fi

# Log directory
if [[ -d "${LOG_DIR}" ]]; then
    log_info "Deleting log directory: ${LOG_DIR}..."
    rm -rf "${LOG_DIR}"
fi

# Config directory
if [[ "${KEEP_CONFIG}" != "true" ]]; then
    if [[ -d "${CONFIG_DIR}" ]]; then
        log_info "Deleting config directory: ${CONFIG_DIR}..."
        rm -rf "${CONFIG_DIR}"
    fi
else
    log_info "Keeping config directory: ${CONFIG_DIR}"
fi

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
echo ""
log_info "=========================================="
log_info "RabbitMQ uninstall completed!"
log_info "=========================================="
echo ""
log_info "Removed:"
log_info "  - rabbitmq.service"
log_info "  - ${INSTALL_DIR}"
if [[ "${KEEP_DATA}" != "true" ]]; then
    log_info "  - ${DATA_DIR}"
fi
log_info "  - ${LOG_DIR}"
if [[ "${KEEP_CONFIG}" != "true" ]]; then
    log_info "  - ${CONFIG_DIR}"
fi
log_info "  - Symlinks in /usr/local/bin/"
echo ""
log_warn "Scripts NOT removed (in ${SCRIPT_DIR}/):"
log_warn "  - v2_setup_rabbitmq.sh"
log_warn "  - rabbitmq-server-generic-unix-*.tar.xz"
echo ""
log_info "To remove: rm -rf ${SCRIPT_DIR}"

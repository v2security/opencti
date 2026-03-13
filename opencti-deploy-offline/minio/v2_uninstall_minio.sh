#!/bin/bash
#===============================================================================
# v2_uninstall_minio.sh - MinIO Complete Uninstall (gỡ bỏ hoàn toàn)
#===============================================================================
#
# MÔ TẢ:
#   Script gỡ bỏ hoàn toàn MinIO: stop service, xóa files, xóa config.
#   CẢNH BÁO: Script này sẽ XÓA TẤT CẢ DATA!
#
# INPUT:
#   Environment variables (tùy chọn):
#     - KEEP_DATA=true     : Giữ lại data directory (default: false - xóa hết)
#     - KEEP_CONFIG=true   : Giữ lại config files (default: false - xóa hết)
#
# OUTPUT:
#   Removed:
#     - MinIO service stopped and disabled
#     - /var/lib/minio/     (data - trừ khi KEEP_DATA=true)
#     - /var/log/minio/     (logs)
#     - /etc/minio/         (config - trừ khi KEEP_CONFIG=true)
#     - /etc/systemd/system/minio.service
#
#   Kept (binaries - phải xóa thủ công):
#     - /usr/local/bin/minio
#     - /usr/local/bin/mc
#     - /usr/local/bin/v2_*.sh
#
# USAGE:
#   # Gỡ hoàn toàn (xóa data + config)
#   bash /usr/local/bin/v2_uninstall_minio.sh
#
#   # Giữ lại data
#   KEEP_DATA=true bash /usr/local/bin/v2_uninstall_minio.sh
#
#   # Giữ lại config
#   KEEP_CONFIG=true bash /usr/local/bin/v2_uninstall_minio.sh
#
#   # Giữ cả data và config
#   KEEP_DATA=true KEEP_CONFIG=true bash /usr/local/bin/v2_uninstall_minio.sh
#
# LƯU Ý:
#   - Script yêu cầu quyền root
#   - CẢNH BÁO: Sẽ xóa tất cả data nếu không set KEEP_DATA=true
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

DATA_DIR="/var/lib/minio"
LOG_DIR="/var/log/minio"
CONFIG_DIR="/etc/minio"
SERVICE_FILE="/etc/systemd/system/minio.service"

#-------------------------------------------------------------------------------
# Info
#-------------------------------------------------------------------------------
echo ""
log_warn "=========================================="
log_warn "       MINIO UNINSTALL                   "
log_warn "=========================================="
log_info "  KEEP_DATA=${KEEP_DATA}"
log_info "  KEEP_CONFIG=${KEEP_CONFIG}"
echo ""

#-------------------------------------------------------------------------------
# Stop and disable service
#-------------------------------------------------------------------------------
log_info "Stopping minio service..."

if systemctl is-active --quiet minio 2>/dev/null; then
    systemctl stop minio || true
fi

if systemctl is-enabled --quiet minio 2>/dev/null; then
    systemctl disable minio || true
fi

# Also run stop script directly
if [[ -f "${SCRIPT_DIR}/v2_stop_minio.sh" ]]; then
    bash "${SCRIPT_DIR}/v2_stop_minio.sh" || true
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
# Remove directories
#-------------------------------------------------------------------------------
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
log_info "MinIO uninstall completed!"
log_info "=========================================="
echo ""
log_info "Removed:"
log_info "  - minio.service (stopped + disabled)"
if [[ "${KEEP_DATA}" != "true" ]]; then
    log_info "  - ${DATA_DIR}"
fi
log_info "  - ${LOG_DIR}"
if [[ "${KEEP_CONFIG}" != "true" ]]; then
    log_info "  - ${CONFIG_DIR}"
fi
echo ""
log_warn "Binaries NOT removed (manual cleanup):"
log_warn "  - ${SCRIPT_DIR}/minio"
log_warn "  - ${SCRIPT_DIR}/mc"
log_warn "  - ${SCRIPT_DIR}/v2_*.sh"
echo ""
log_info "To remove binaries: rm -f ${SCRIPT_DIR}/{minio,mc,v2_*.sh}"

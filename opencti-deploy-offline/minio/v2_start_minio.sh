#!/bin/bash
#===============================================================================
# v2_start_minio.sh - MinIO Start Script (gọi bởi systemd ExecStart)
#===============================================================================
#
# MÔ TẢ:
#   Script khởi động MinIO server. Được gọi bởi systemd khi start service.
#   Load config từ /etc/minio/minio.conf và exec minio binary.
#
# INPUT:
#   Files (cùng thư mục với script):
#     - minio              : MinIO server binary (bắt buộc)
#
#   Config files:
#     - /etc/minio/minio.conf : Config file (tùy chọn, dùng default nếu không có)
#
#   Environment variables (từ systemd hoặc config file):
#     - MINIO_USER         : User sở hữu (default: admin)
#     - MINIO_GROUP        : Group sở hữu (default: admin)
#     - MINIO_ROOT_USER    : MinIO admin username
#     - MINIO_ROOT_PASSWORD: MinIO admin password
#     - MINIO_VOLUMES      : Data directory path
#     - MINIO_OPTS         : Additional server options
#
# OUTPUT:
#   Services:
#     - MinIO API server    : http://0.0.0.0:9000
#     - MinIO Console (WebUI): http://0.0.0.0:9001
#
#   Logs:
#     - stdout/stderr → systemd journal (journalctl -u minio)
#
# OWNER:
#   Mặc định: admin:admin (phải khớp với minio.service)
#   Được đọc từ /etc/minio/minio.conf hoặc env var
#
# USAGE:
#   # Gọi bởi systemd (ExecStart)
#   ExecStart=/usr/local/bin/v2_start_minio.sh
#
#   # Chạy thủ công (debug)
#   bash /usr/local/bin/v2_start_minio.sh
#
# LƯU Ý:
#   - Script sử dụng exec để thay thế shell process bằng minio
#   - Điều này đảm bảo systemd có thể gửi signal trực tiếp đến minio
#   - MINIO_USER/GROUP phải khớp với v2_setup_minio.sh và minio.service
#
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MINIO_BINARY="${SCRIPT_DIR}/minio"
CONFIG_FILE="/etc/minio/minio.conf"

# Default owner - có thể override bằng env var hoặc config file
MINIO_USER="${MINIO_USER:-admin}"
MINIO_GROUP="${MINIO_GROUP:-admin}"

#-------------------------------------------------------------------------------
# Load config (override defaults)
#-------------------------------------------------------------------------------
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
else
    echo "WARNING: Config file not found: ${CONFIG_FILE}, using defaults" >&2
fi

# Set defaults for MinIO settings (sau khi load config)
MINIO_ROOT_USER="${MINIO_ROOT_USER:-minioadmin}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-minioadmin123}"
MINIO_VOLUMES="${MINIO_VOLUMES:-/var/lib/minio/data}"
MINIO_OPTS="${MINIO_OPTS:---console-address :9001}"

#-------------------------------------------------------------------------------
# Check binary exists
#-------------------------------------------------------------------------------
if [[ ! -x "${MINIO_BINARY}" ]]; then
    echo "ERROR: minio binary not found or not executable: ${MINIO_BINARY}" >&2
    exit 1
fi

#-------------------------------------------------------------------------------
# Export environment variables for MinIO
#-------------------------------------------------------------------------------
export MINIO_ROOT_USER
export MINIO_ROOT_PASSWORD

#-------------------------------------------------------------------------------
# Start MinIO server
# exec replaces the shell process with minio (proper signal handling)
#-------------------------------------------------------------------------------
echo "=============================================="
echo "Starting MinIO server..."
echo "=============================================="
echo "  User   : ${MINIO_USER}"
echo "  API    : http://0.0.0.0:9000"
echo "  Console: http://0.0.0.0:9001"
echo "  Data   : ${MINIO_VOLUMES}"
echo "=============================================="

exec "${MINIO_BINARY}" server ${MINIO_OPTS} ${MINIO_VOLUMES}

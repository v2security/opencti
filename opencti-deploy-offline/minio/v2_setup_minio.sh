#!/bin/bash
#===============================================================================
# v2_setup_minio.sh - MinIO First Boot Setup (chạy 1 lần duy nhất)
#===============================================================================
#
# MÔ TẢ:
#   Script khởi tạo MinIO lần đầu: tạo thư mục, config, set permissions.
#   Sử dụng marker file để đảm bảo chỉ chạy 1 lần.
#
# INPUT:
#   Files (cùng thư mục với script):
#     - minio              : MinIO server binary (bắt buộc)
#     - mc                 : MinIO client binary (tùy chọn)
#
#   Environment variables (tùy chọn):
#     - MINIO_USER         : User sở hữu (default: admin)
#     - MINIO_GROUP        : Group sở hữu (default: admin)
#     - MINIO_ROOT_USER    : MinIO admin username (default: minioadmin)
#     - MINIO_ROOT_PASSWORD: MinIO admin password (default: minioadmin123)
#
# OUTPUT:
#   Directories:
#     - /var/lib/minio/data/     : Data directory (owner: MINIO_USER)
#     - /var/log/minio/          : Log directory (owner: MINIO_USER)
#     - /etc/minio/              : Config directory
#
#   Files:
#     - /etc/minio/minio.conf    : Config file (tạo nếu chưa có)
#     - /var/lib/minio/.setup_done : Marker file (ngăn chạy lại)
#
# OWNER:
#   Mặc định: admin:admin
#   Thay đổi bằng cách set MINIO_USER và MINIO_GROUP trước khi chạy:
#     MINIO_USER=root MINIO_GROUP=root bash v2_setup_minio.sh
#
# USAGE:
#   # Chạy với user mặc định (admin)
#   bash /usr/local/bin/v2_setup_minio.sh
#
#   # Chạy với user root
#   MINIO_USER=root MINIO_GROUP=root bash /usr/local/bin/v2_setup_minio.sh
#
# LƯU Ý:
#   - Script yêu cầu quyền root để tạo thư mục và set permissions
#   - User MINIO_USER phải tồn tại trước khi chạy script
#   - Chỉ chạy 1 lần (first boot), các lần sau sẽ skip
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
MARKER_FILE="/var/lib/minio/.setup_done"

# Service owner - có thể thay đổi: admin, root, hoặc user khác
# Đầu vào: MINIO_USER=root MINIO_GROUP=root bash v2_setup_minio.sh
MINIO_USER="${MINIO_USER:-admin}"
MINIO_GROUP="${MINIO_GROUP:-admin}"

DATA_DIR="/var/lib/minio/data"
LOG_DIR="/var/log/minio"
CONFIG_DIR="/etc/minio"
CONFIG_FILE="${CONFIG_DIR}/minio.conf"

# Default MinIO settings
MINIO_ROOT_USER="${MINIO_ROOT_USER:-minioadmin}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-minioadmin123}"
MINIO_VOLUMES="${MINIO_VOLUMES:-/var/lib/minio/data}"
MINIO_OPTS="${MINIO_OPTS:---console-address :9001}"

#-------------------------------------------------------------------------------
# Check if already setup
#-------------------------------------------------------------------------------
if [[ -f "$MARKER_FILE" ]]; then
    log_info "MinIO already setup (marker: $MARKER_FILE). Skipping."
    exit 0
fi

log_info "Starting MinIO first-boot setup..."
log_info "Owner: ${MINIO_USER}:${MINIO_GROUP}"

#-------------------------------------------------------------------------------
# Verify binaries exist in /usr/local/bin/
#-------------------------------------------------------------------------------
if [[ ! -f "/usr/local/bin/minio" ]]; then
    log_error "minio binary not found at /usr/local/bin/minio"
    log_error "Please mount minio binary to /usr/local/bin/"
    exit 1
fi

if [[ ! -f "/usr/local/bin/mc" ]]; then
    log_warn "mc binary not found at /usr/local/bin/mc (optional)"
fi

log_info "Binaries verified:"
log_info "  /usr/local/bin/minio"
[[ -f "/usr/local/bin/mc" ]] && log_info "  /usr/local/bin/mc"

#-------------------------------------------------------------------------------
# Verify user and group exist
#-------------------------------------------------------------------------------
if ! getent passwd "${MINIO_USER}" > /dev/null 2>&1; then
    log_error "User '${MINIO_USER}' does not exist!"
    log_error "Please create user first or change MINIO_USER variable"
    exit 1
fi

if ! getent group "${MINIO_GROUP}" > /dev/null 2>&1; then
    log_error "Group '${MINIO_GROUP}' does not exist!"
    log_error "Please create group first or change MINIO_GROUP variable"
    exit 1
fi

#-------------------------------------------------------------------------------
# Create directories
#-------------------------------------------------------------------------------
log_info "Creating directories..."

mkdir -p "${DATA_DIR}"
mkdir -p "${LOG_DIR}"
mkdir -p "${CONFIG_DIR}"

# Chown parent directories too
chown "${MINIO_USER}:${MINIO_GROUP}" /var/lib/minio
chown -R "${MINIO_USER}:${MINIO_GROUP}" "${DATA_DIR}"
chown -R "${MINIO_USER}:${MINIO_GROUP}" "${LOG_DIR}"
chmod 750 /var/lib/minio
chmod 750 "${DATA_DIR}"
chmod 750 "${LOG_DIR}"

#-------------------------------------------------------------------------------
# Binaries are pre-mounted to /usr/local/bin/ (read-only)
# No need to chmod — they should be executable from host
#-------------------------------------------------------------------------------
log_info "Binaries at /usr/local/bin/ (pre-mounted)"

#-------------------------------------------------------------------------------
# Create config file if not exists
#-------------------------------------------------------------------------------
if [[ ! -f "${CONFIG_FILE}" ]]; then
    log_info "Creating config file: ${CONFIG_FILE}"
    cat > "${CONFIG_FILE}" << EOF
# MinIO Configuration
# This file is sourced by v2_start_minio.sh and minio.service
# Owner: ${MINIO_USER}:${MINIO_GROUP}

MINIO_USER="${MINIO_USER}"
MINIO_GROUP="${MINIO_GROUP}"
MINIO_ROOT_USER="${MINIO_ROOT_USER}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD}"
MINIO_VOLUMES="${MINIO_VOLUMES}"
MINIO_OPTS="${MINIO_OPTS}"
EOF
    chmod 640 "${CONFIG_FILE}"
    chown root:${MINIO_GROUP} "${CONFIG_FILE}"
else
    log_info "Config file exists: ${CONFIG_FILE}"
fi

#-------------------------------------------------------------------------------
# Create marker file
#-------------------------------------------------------------------------------
mkdir -p "$(dirname "${MARKER_FILE}")"
touch "${MARKER_FILE}"
chown "${MINIO_USER}:${MINIO_GROUP}" "${MARKER_FILE}"

log_info "=============================================="
log_info "MinIO setup completed successfully!"
log_info "=============================================="
log_info "Owner      : ${MINIO_USER}:${MINIO_GROUP}"
log_info "Config     : ${CONFIG_FILE}"
log_info "Data dir   : ${DATA_DIR}"
log_info "Log dir    : ${LOG_DIR}"
log_info ""
log_info "Scripts and systemd service should be pre-mounted:"
log_info "  /usr/local/bin/v2_start_minio.sh"
log_info "  /usr/local/bin/v2_stop_minio.sh"
log_info "  /etc/systemd/system/minio.service"
log_info ""
log_info "Reloading systemd..."
systemctl daemon-reload 2>/dev/null || true

#-------------------------------------------------------------------------------
# Start MinIO temporarily to create default bucket
#-------------------------------------------------------------------------------
BUCKET_NAME="${MINIO_BUCKET_NAME:-opencti-bucket}"

if [[ -f "/usr/local/bin/mc" ]]; then
    log_info "Starting MinIO temporarily to create bucket '${BUCKET_NAME}'..."

    # Start minio in background
    su -s /bin/bash "${MINIO_USER}" -c "
        MINIO_ROOT_USER='${MINIO_ROOT_USER}' \
        MINIO_ROOT_PASSWORD='${MINIO_ROOT_PASSWORD}' \
        /usr/local/bin/minio server ${MINIO_OPTS} ${MINIO_VOLUMES} &
    "
    MINIO_TMP_PID=$!

    # Wait for MinIO to be ready
    for i in $(seq 1 30); do
        if curl -s -o /dev/null http://127.0.0.1:9000/minio/health/live 2>/dev/null; then
            break
        fi
        sleep 1
    done

    # Create alias + bucket
    /usr/local/bin/mc alias set local http://127.0.0.1:9000 "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" --api S3v4 2>/dev/null
    if /usr/local/bin/mc mb --ignore-existing local/"${BUCKET_NAME}" 2>/dev/null; then
        log_info "Bucket '${BUCKET_NAME}' created successfully"
    else
        log_warn "Failed to create bucket '${BUCKET_NAME}' — create manually after start"
    fi

    # Stop temporary MinIO
    kill "$MINIO_TMP_PID" 2>/dev/null || pkill -f "minio server" 2>/dev/null || true
    wait "$MINIO_TMP_PID" 2>/dev/null || true
    sleep 1
else
    log_warn "mc not found — cannot auto-create bucket '${BUCKET_NAME}'"
    log_warn "After starting MinIO, run:"
    log_warn "  mc alias set local http://127.0.0.1:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD}"
    log_warn "  mc mb local/${BUCKET_NAME}"
fi

log_info ""
log_info "Next steps:"
log_info "  systemctl enable --now minio"

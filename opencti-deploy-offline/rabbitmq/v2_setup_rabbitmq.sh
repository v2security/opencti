#!/bin/bash
#===============================================================================
# v2_setup_rabbitmq.sh - RabbitMQ First Boot Setup (chạy 1 lần duy nhất)
#===============================================================================
#
# MÔ TẢ:
#   Script khởi tạo RabbitMQ lần đầu: extract tarball, tạo thư mục, config.
#   Sử dụng marker file để đảm bảo chỉ chạy 1 lần.
#
# INPUT:
#   Files (cùng thư mục với script):
#     - rabbitmq-server-generic-unix-*.tar.xz : RabbitMQ tarball (bắt buộc)
#
#   Environment variables (tùy chọn):
#     - RABBITMQ_USER      : User sở hữu (default: admin)
#     - RABBITMQ_GROUP     : Group sở hữu (default: admin)
#     - RABBITMQ_NODENAME  : Node name (default: rabbit@localhost)
#     - RABBITMQ_DEFAULT_USER : Default admin user (default: admin)
#     - RABBITMQ_DEFAULT_PASS : Default admin password (default: admin123)
#
# OUTPUT:
#   Directories:
#     - /opt/rabbitmq/              : RabbitMQ installation (extracted)
#     - /var/lib/rabbitmq/          : Data directory (mnesia)
#     - /var/log/rabbitmq/          : Log directory
#     - /etc/rabbitmq/              : Config directory
#
#   Files:
#     - /etc/rabbitmq/rabbitmq.conf     : Main config
#     - /etc/rabbitmq/rabbitmq-env.conf : Environment config
#     - /var/lib/rabbitmq/.setup_done   : Marker file
#
#   Symlinks (in /usr/local/bin/):
#     - rabbitmqctl, rabbitmq-server, rabbitmq-plugins, etc.
#
# OWNER:
#   Mặc định: admin:admin
#   Thay đổi: RABBITMQ_USER=root RABBITMQ_GROUP=root bash v2_setup_rabbitmq.sh
#
# USAGE:
#   # Với admin user (mặc định)
#   bash v2_setup_rabbitmq.sh
#
#   # Với user khác
#   RABBITMQ_USER=master RABBITMQ_GROUP=master bash v2_setup_rabbitmq.sh
#
# LƯU Ý:
#   - Script yêu cầu quyền root để tạo thư mục và set permissions
#   - User RABBITMQ_USER phải tồn tại trước khi chạy script
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
MARKER_FILE="/var/lib/rabbitmq/.setup_done"

# Service owner - có thể thay đổi: admin, root, hoặc user khác
RABBITMQ_USER="${RABBITMQ_USER:-admin}"
RABBITMQ_GROUP="${RABBITMQ_GROUP:-admin}"

# Installation paths
INSTALL_DIR="/opt/rabbitmq"
DATA_DIR="/var/lib/rabbitmq"
LOG_DIR="/var/log/rabbitmq"
CONFIG_DIR="/etc/rabbitmq"

# RabbitMQ settings
RABBITMQ_NODENAME="${RABBITMQ_NODENAME:-rabbit@localhost}"
RABBITMQ_DEFAULT_USER="${RABBITMQ_DEFAULT_USER:-admin}"
RABBITMQ_DEFAULT_PASS="${RABBITMQ_DEFAULT_PASS:-admin123}"

#-------------------------------------------------------------------------------
# Check if already setup
#-------------------------------------------------------------------------------
if [[ -f "$MARKER_FILE" ]]; then
    log_info "RabbitMQ already setup (marker: $MARKER_FILE). Skipping."
    exit 0
fi

log_info "Starting RabbitMQ first-boot setup..."
log_info "Owner: ${RABBITMQ_USER}:${RABBITMQ_GROUP}"

#-------------------------------------------------------------------------------
# Find tarball
#-------------------------------------------------------------------------------
TARBALL=$(find "${SCRIPT_DIR}" -maxdepth 1 -name "rabbitmq-server-generic-unix-*.tar.xz" | head -1)

if [[ -z "${TARBALL}" || ! -f "${TARBALL}" ]]; then
    log_error "RabbitMQ tarball not found in ${SCRIPT_DIR}"
    log_error "Expected: rabbitmq-server-generic-unix-*.tar.xz"
    exit 1
fi

log_info "Found tarball: ${TARBALL}"

#-------------------------------------------------------------------------------
# Verify user and group exist
#-------------------------------------------------------------------------------
if ! getent passwd "${RABBITMQ_USER}" > /dev/null 2>&1; then
    log_error "User '${RABBITMQ_USER}' does not exist!"
    log_error "Please create user first or change RABBITMQ_USER variable"
    exit 1
fi

if ! getent group "${RABBITMQ_GROUP}" > /dev/null 2>&1; then
    log_error "Group '${RABBITMQ_GROUP}' does not exist!"
    log_error "Please create group first or change RABBITMQ_GROUP variable"
    exit 1
fi

#-------------------------------------------------------------------------------
# Create directories
#-------------------------------------------------------------------------------
log_info "Creating directories..."

mkdir -p "${INSTALL_DIR}"
mkdir -p "${DATA_DIR}"
mkdir -p "${LOG_DIR}"
mkdir -p "${CONFIG_DIR}"

#-------------------------------------------------------------------------------
# Extract tarball
#-------------------------------------------------------------------------------
log_info "Extracting RabbitMQ to ${INSTALL_DIR}..."

# Extract to temp, then move contents
TEMP_DIR=$(mktemp -d)
tar -xJf "${TARBALL}" -C "${TEMP_DIR}"

# Find extracted directory (rabbitmq_server-x.x.x)
EXTRACTED_DIR=$(find "${TEMP_DIR}" -maxdepth 1 -type d -name "rabbitmq_server-*" | head -1)

if [[ -z "${EXTRACTED_DIR}" ]]; then
    log_error "Failed to find extracted RabbitMQ directory"
    rm -rf "${TEMP_DIR}"
    exit 1
fi

# Move contents to install dir
rm -rf "${INSTALL_DIR:?}"/*
mv "${EXTRACTED_DIR}"/* "${INSTALL_DIR}/"
rm -rf "${TEMP_DIR}"

log_info "RabbitMQ extracted to ${INSTALL_DIR}"

#-------------------------------------------------------------------------------
# Set permissions
#-------------------------------------------------------------------------------
log_info "Setting permissions..."

chown -R "${RABBITMQ_USER}:${RABBITMQ_GROUP}" "${INSTALL_DIR}"
chown -R "${RABBITMQ_USER}:${RABBITMQ_GROUP}" "${DATA_DIR}"
chown -R "${RABBITMQ_USER}:${RABBITMQ_GROUP}" "${LOG_DIR}"
chown -R "${RABBITMQ_USER}:${RABBITMQ_GROUP}" "${CONFIG_DIR}" 2>/dev/null || log_warn "Some config files are read-only (bind mount?), skipping chown"

chmod 755 "${INSTALL_DIR}"
chmod 750 "${DATA_DIR}"
chmod 750 "${LOG_DIR}"
chmod 755 "${CONFIG_DIR}"

#-------------------------------------------------------------------------------
# Create symlinks in /usr/local/bin
#-------------------------------------------------------------------------------
log_info "Creating symlinks in /usr/local/bin..."

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
    if [[ -f "${INSTALL_DIR}/sbin/${bin}" ]]; then
        ln -sf "${INSTALL_DIR}/sbin/${bin}" "/usr/local/bin/${bin}"
        log_info "  Linked: ${bin}"
    fi
done

#-------------------------------------------------------------------------------
# Create config files
#-------------------------------------------------------------------------------
if [[ ! -f "${CONFIG_DIR}/rabbitmq-env.conf" ]]; then
    log_info "Creating ${CONFIG_DIR}/rabbitmq-env.conf..."
    cat > "${CONFIG_DIR}/rabbitmq-env.conf" << EOF
# RabbitMQ Environment Configuration
# Owner: ${RABBITMQ_USER}:${RABBITMQ_GROUP}

RABBITMQ_USER="${RABBITMQ_USER}"
RABBITMQ_GROUP="${RABBITMQ_GROUP}"

# Node name
RABBITMQ_NODENAME="${RABBITMQ_NODENAME}"

# Directories
RABBITMQ_BASE="${DATA_DIR}"
RABBITMQ_MNESIA_BASE="${DATA_DIR}/mnesia"
RABBITMQ_LOG_BASE="${LOG_DIR}"
RABBITMQ_CONFIG_FILE="${CONFIG_DIR}/rabbitmq"

# Erlang cookie location
HOME="${DATA_DIR}"
EOF
    chown "${RABBITMQ_USER}:${RABBITMQ_GROUP}" "${CONFIG_DIR}/rabbitmq-env.conf"
    chmod 640 "${CONFIG_DIR}/rabbitmq-env.conf"
fi

if [[ ! -f "${CONFIG_DIR}/rabbitmq.conf" ]]; then
    log_info "Creating ${CONFIG_DIR}/rabbitmq.conf..."
    cat > "${CONFIG_DIR}/rabbitmq.conf" << EOF
# RabbitMQ Configuration
# Owner: ${RABBITMQ_USER}:${RABBITMQ_GROUP}

# Listeners
listeners.tcp.default = 5672

# Management plugin
management.tcp.port = 15672

# Default user (created on first start)
default_user = ${RABBITMQ_DEFAULT_USER}
default_pass = ${RABBITMQ_DEFAULT_PASS}
default_user_tags.administrator = true
default_permissions.configure = .*
default_permissions.read = .*
default_permissions.write = .*

# Logging
log.file.level = info
log.console = false
log.console.level = info

# Memory and disk limits
# vm_memory_high_watermark.relative = 0.4
# disk_free_limit.relative = 1.0
EOF
    chown "${RABBITMQ_USER}:${RABBITMQ_GROUP}" "${CONFIG_DIR}/rabbitmq.conf"
    chmod 640 "${CONFIG_DIR}/rabbitmq.conf"
fi

#-------------------------------------------------------------------------------
# Create Erlang cookie
#-------------------------------------------------------------------------------
COOKIE_FILE="${DATA_DIR}/.erlang.cookie"
if [[ ! -f "${COOKIE_FILE}" ]]; then
    log_info "Creating Erlang cookie..."
    # Generate random cookie
    COOKIE=$(openssl rand -hex 20 2>/dev/null || head -c 40 /dev/urandom | od -An -tx1 | tr -d ' \n')
    echo "${COOKIE}" > "${COOKIE_FILE}"
    chown "${RABBITMQ_USER}:${RABBITMQ_GROUP}" "${COOKIE_FILE}"
    chmod 400 "${COOKIE_FILE}"
fi

#-------------------------------------------------------------------------------
# Enable management plugin
#-------------------------------------------------------------------------------
log_info "Enabling management plugin..."
ENABLED_PLUGINS_FILE="${CONFIG_DIR}/enabled_plugins"
if [[ -w "${ENABLED_PLUGINS_FILE}" ]] || [[ ! -f "${ENABLED_PLUGINS_FILE}" ]]; then
    echo "[rabbitmq_management]." > "${ENABLED_PLUGINS_FILE}"
    chown "${RABBITMQ_USER}:${RABBITMQ_GROUP}" "${ENABLED_PLUGINS_FILE}" 2>/dev/null || true
else
    log_warn "enabled_plugins is read-only (bind mount?), skipping write"
fi

#-------------------------------------------------------------------------------
# Create marker file
#-------------------------------------------------------------------------------
touch "${MARKER_FILE}"
chown "${RABBITMQ_USER}:${RABBITMQ_GROUP}" "${MARKER_FILE}"

log_info "=============================================="
log_info "RabbitMQ setup completed successfully!"
log_info "=============================================="
log_info "Owner       : ${RABBITMQ_USER}:${RABBITMQ_GROUP}"
log_info "Install dir : ${INSTALL_DIR}"
log_info "Data dir    : ${DATA_DIR}"
log_info "Log dir     : ${LOG_DIR}"
log_info "Config dir  : ${CONFIG_DIR}"
log_info ""
log_info "Default credentials:"
log_info "  User: ${RABBITMQ_DEFAULT_USER}"
log_info "  Pass: ${RABBITMQ_DEFAULT_PASS}"
log_info ""
log_info "Ports:"
log_info "  AMQP: 5672"
log_info "  Management: 15672"
log_info ""
log_info "Scripts and systemd service should be pre-mounted:"
log_info "  /usr/local/bin/v2_start_rabbitmq.sh"
log_info "  /usr/local/bin/v2_stop_rabbitmq.sh"
log_info "  /etc/systemd/system/rabbitmq.service"
log_info ""
log_info "Reloading systemd..."
systemctl daemon-reload 2>/dev/null || true
log_info ""
log_info "Next steps:"
log_info "  systemctl enable --now rabbitmq"

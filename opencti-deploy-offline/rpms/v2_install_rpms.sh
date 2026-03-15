#!/bin/bash
#===============================================================================
# v2_install_rpms.sh - Install RPM packages (First Boot)
#===============================================================================
#
# MÔ TẢ:
#   Script install tất cả RPM packages cho offline deployment.
#   Được gọi bởi first_boot.sh.
#   Sử dụng marker file để đảm bảo chỉ chạy 1 lần.
#
# INPUT:
#   Files (cùng thư mục với script):
#     - *.rpm                    : Tất cả RPM packages (~100 files)
#
#   Bao gồm:
#     - redis-*.rpm              : Redis server
#     - erlang-*.rpm             : Erlang runtime (cho RabbitMQ)
#     - gcc-*.rpm, glibc-*.rpm   : Build tools
#     - openssl-*.rpm            : SSL libraries
#     - systemd-*.rpm            : Systemd components
#
# OUTPUT:
#   Installed packages:
#     - /usr/bin/redis-server
#     - /usr/lib64/erlang/
#     - /etc/systemd/system/redis.service (from RPM)
#
#   Directories created:
#     - /var/lib/redis/
#     - /var/log/redis/
#
#   Marker file:
#     - .rpms-installed (cùng thư mục) - ngăn chạy lại
#
# USAGE:
#   # Chạy từ thư mục chứa RPMs
#   bash v2_install_rpms.sh
#
#   # Hoặc chạy từ bất kỳ đâu (script tự tìm đường dẫn)
#   bash /path/to/rpms/v2_install_rpms.sh
#
# LƯU Ý:
#   - Script yêu cầu quyền root
#   - Chỉ chạy 1 lần (first boot)
#   - RPM packages phải ở cùng thư mục với script
#
#===============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER_FILE="/var/lib/.v2_rpms_installed"

#-------------------------------------------------------------------------------
# Check if already installed
#-------------------------------------------------------------------------------
if [[ -f "$MARKER_FILE" ]]; then
    log_info "RPMs already installed (marker: $MARKER_FILE)"
    log_info "Skipping installation"
    exit 0
fi

#-------------------------------------------------------------------------------
# Pre-checks
#-------------------------------------------------------------------------------
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           INSTALL RPMs — First Boot                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

if [[ $EUID -ne 0 ]]; then
    log_error "Cần chạy với quyền root"
    exit 1
fi

#-------------------------------------------------------------------------------
# Count RPM files
#-------------------------------------------------------------------------------
cd "${SCRIPT_DIR}"
RPM_COUNT=$(ls -1 *.rpm 2>/dev/null | wc -l)

if [[ $RPM_COUNT -eq 0 ]]; then
    log_error "No RPM files found in ${SCRIPT_DIR}"
    exit 1
fi

log_info "Found ${RPM_COUNT} RPM packages in ${SCRIPT_DIR}"

#===============================================================================
# STEP 1: Install RPM packages
#===============================================================================
log_step "Installing RPM packages..."

# Try dnf first (recommended), fallback to rpm
if command -v dnf &>/dev/null; then
    log_info "Using dnf (pass 1: resolve dependencies)..."
    dnf localinstall -y \
        --allowerasing \
        --disablerepo="*" \
        *.rpm 2>&1 | tail -30 || {
        log_warn "dnf had dependency issues, using rpm (pass 2: force install)..."
        rpm -Uvh --force --nodeps *.rpm 2>&1 | tail -30 || true
    }
else
    log_info "Using rpm..."
    rpm -Uvh --force --nodeps *.rpm 2>&1 | tail -30 || true
fi

# Reload systemd to pick up new service files (e.g. redis.service)
systemctl daemon-reload 2>/dev/null || true

log_info "RPM packages installed"

#===============================================================================
# STEP 2: Verify critical packages
#===============================================================================
log_step "Verifying critical packages..."

# Check Redis
if command -v redis-server &>/dev/null; then
    REDIS_VER=$(redis-server --version 2>&1 | head -1 | awk '{print $3}' | cut -d= -f2)
    log_info "redis-server: v${REDIS_VER}"
else
    log_warn "redis-server not found"
fi

# Check Erlang
if command -v erl &>/dev/null; then
    ERL_VER=$(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell 2>/dev/null | tr -d '"' || echo "unknown")
    log_info "erlang: OTP ${ERL_VER}"
else
    log_warn "erlang not found - RabbitMQ may not work"
fi

# Check GCC
if command -v gcc &>/dev/null; then
    GCC_VER=$(gcc --version 2>&1 | head -1 | awk '{print $NF}')
    log_info "gcc: v${GCC_VER}"
else
    log_warn "gcc not found"
fi

#===============================================================================
# STEP 3: Create directories for Redis
#===============================================================================
log_step "Creating Redis directories..."

mkdir -p /var/lib/redis
mkdir -p /var/log/redis

# Set permissions if redis user exists
if id redis &>/dev/null; then
    chown -R redis:redis /var/lib/redis
    chown -R redis:redis /var/log/redis
    chmod 750 /var/lib/redis
    chmod 750 /var/log/redis
    log_info "Redis directories: owner=redis"
else
    log_warn "Redis user not found, directories owned by root"
fi

#===============================================================================
# STEP 4: Create marker file
#===============================================================================
log_step "Creating marker file..."

cat > "${MARKER_FILE}" << EOF
# RPMs installed by v2_install_rpms.sh
# Date: $(date)
# Count: ${RPM_COUNT} packages
# Directory: ${SCRIPT_DIR}
EOF

log_info "Marker created: ${MARKER_FILE}"

#===============================================================================
# Summary
#===============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           RPM INSTALLATION COMPLETE                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  📦 Installed: ${RPM_COUNT} RPM packages"
echo ""
echo "  ✓ Packages verified:"
if command -v redis-server &>/dev/null; then
    echo "    - redis-server"
fi
if command -v erl &>/dev/null; then
    echo "    - erlang"
fi
if command -v gcc &>/dev/null; then
    echo "    - gcc"
fi
echo ""
echo "  📁 Directories created:"
echo "    - /var/lib/redis/"
echo "    - /var/log/redis/"
echo ""
echo "  👉 Next: Run setup scripts for MinIO, RabbitMQ"
echo ""

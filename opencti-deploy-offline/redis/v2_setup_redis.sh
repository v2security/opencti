#!/bin/bash
#===============================================================================
# v2_setup_redis.sh — Redis First Boot Setup (chạy 1 lần sau RPM install)
#===============================================================================
#
# MÔ TẢ:
#   Setup Redis cho OpenCTI offline deployment:
#   1. Verify redis-server + redis.conf
#   2. Tạo thư mục + permissions
#   3. Deploy systemd override (auto-restart, OOM protect)
#   4. Tune kernel: vm.overcommit_memory=1, disable THP
#
# YÊU CẦU:
#   - Redis RPM đã cài (từ v2_install_rpms.sh)
#   - /etc/redis/redis.conf đã deploy (từ v2_unpack_opencti_infra.sh)
#   - Quyền root
#
# USAGE:
#   v2_setup_redis.sh        # chạy từ /usr/local/bin/
#
#===============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

MARKER_FILE="/var/lib/redis/.setup_done"

#-------------------------------------------------------------------------------
# Skip if already done
#-------------------------------------------------------------------------------
if [[ -f "$MARKER_FILE" ]]; then
    log_info "Redis already setup (marker: $MARKER_FILE). Skipping."
    exit 0
fi

if [[ $EUID -ne 0 ]]; then
    log_error "Cần chạy với quyền root"
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           SETUP REDIS — First Boot                         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

#===============================================================================
# 1. Verify redis-server installed
#===============================================================================
log_step "Checking redis-server..."
if ! command -v redis-server &>/dev/null; then
    log_error "redis-server not found. Install Redis RPM first."
    exit 1
fi
REDIS_VER=$(redis-server --version 2>&1 | awk '{print $3}' | cut -d= -f2)
log_info "redis-server: v${REDIS_VER}"

#===============================================================================
# 2. Kernel tuning
#===============================================================================
log_step "Kernel tuning..."

# vm.overcommit_memory=1: Redis khuyến nghị để BGSAVE fork không bị reject
if [[ "$(cat /proc/sys/vm/overcommit_memory)" != "1" ]]; then
    sysctl -w vm.overcommit_memory=1
    log_info "vm.overcommit_memory = 1"
fi

# Persist across reboot
if ! grep -q "^vm.overcommit_memory" /etc/sysctl.d/99-redis.conf 2>/dev/null; then
    mkdir -p /etc/sysctl.d
    cat > /etc/sysctl.d/99-redis.conf << 'EOF'
# Redis: allow overcommit for fork (BGSAVE/BGREWRITEAOF)
vm.overcommit_memory = 1
EOF
    log_info "Persisted to /etc/sysctl.d/99-redis.conf"
fi

# Disable Transparent Huge Pages (THP)
# THP gây latency spike + memory bloat cho Redis
if [[ -f /sys/kernel/mm/transparent_hugepage/enabled ]]; then
    echo never > /sys/kernel/mm/transparent_hugepage/enabled
    echo never > /sys/kernel/mm/transparent_hugepage/defrag
    log_info "THP disabled (runtime)"
fi

# Persist THP disable across reboot via systemd
if [[ ! -f /etc/systemd/system/disable-thp.service ]]; then
    cat > /etc/systemd/system/disable-thp.service << 'EOF'
[Unit]
Description=Disable Transparent Huge Pages (for Redis)
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=redis.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled && echo never > /sys/kernel/mm/transparent_hugepage/defrag'

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable disable-thp.service
    log_info "THP disable persisted (disable-thp.service)"
fi

#===============================================================================
# 3. Directories + permissions
#===============================================================================
log_step "Creating directories..."

mkdir -p /var/lib/redis /var/log/redis /etc/redis

if id redis &>/dev/null; then
    chown -R redis:redis /var/lib/redis /var/log/redis
    chmod 750 /var/lib/redis /var/log/redis
    log_info "Directories: owner=redis, mode=750"
else
    log_warn "Redis user not found (RPM should create it)"
fi

#===============================================================================
# 4. Verify redis.conf (deployed by v2_unpack_opencti_infra.sh)
#===============================================================================
log_step "Checking redis.conf..."

if [[ -f /etc/redis/redis.conf ]]; then
    chown redis:redis /etc/redis/redis.conf 2>/dev/null || true
    chmod 640 /etc/redis/redis.conf 2>/dev/null || true
    log_info "Verified: /etc/redis/redis.conf"
else
    log_error "/etc/redis/redis.conf not found."
    log_error "Run v2_unpack_opencti_infra.sh first to deploy config files."
    exit 1
fi

#===============================================================================
# 5. Deploy systemd override (inline)
#===============================================================================
log_step "Deploying systemd override..."

OVERRIDE_DIR="/etc/systemd/system/redis.service.d"
mkdir -p "${OVERRIDE_DIR}"

cat > "${OVERRIDE_DIR}/limit.conf" << 'EOF'
[Service]
LimitNOFILE=65536
TimeoutStartSec=90s
TimeoutStopSec=30s
Restart=on-failure
RestartSec=5s
OOMScoreAdjust=-900
EOF
log_info "Deployed: ${OVERRIDE_DIR}/limit.conf"

systemctl daemon-reload

#===============================================================================
# 6. Marker
#===============================================================================
touch "${MARKER_FILE}"
chown redis:redis "${MARKER_FILE}" 2>/dev/null || true

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           REDIS SETUP COMPLETE                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  Config:  /etc/redis/redis.conf"
echo "  Data:    /var/lib/redis/"
echo "  Log:     /var/log/redis/redis.log"
echo "  Kernel:  vm.overcommit_memory=1, THP=never"
echo "  RDB:     DISABLED (save \"\")"
echo ""
log_info "Next steps:"
log_info "  systemctl enable --now redis"

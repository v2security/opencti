#!/bin/bash
###############################################################################
# v2_unpack_opencti.sh — Giải nén + đặt files vào đúng chỗ trên Rocky Linux 9
#
# Script COPY FILES vào đúng path cuối cùng, xóa folder tạm sau khi xong.
# Sau khi chạy xong, bạn tự chạy setup + start theo hướng dẫn.
#
# Chạy TRÊN MÁY TARGET (offline) với quyền root.
#
# Usage:
#   cd /opt
#   tar xzf opencti-offline-deploy.tar.gz
#   bash v2_unpack_opencti.sh
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

log()   { echo -e "\e[32m[DEPLOY]\e[0m $1"; }
warn()  { echo -e "\e[33m[DEPLOY]\e[0m $1"; }
error() { echo -e "\e[31m[DEPLOY]\e[0m $1" >&2; exit 1; }

[[ $EUID -eq 0 ]] || error "Must run as root"
[[ -f "rpms/v2_install_rpms.sh" ]] || error "rpms/ not found — đúng thư mục chưa?"

if [[ -f /etc/rocky-release ]]; then
    log "OS: $(cat /etc/rocky-release)"
else
    warn "Không phải Rocky Linux — có thể gặp vấn đề"
fi

log "══════════════════════════════════════════════════════════════"
log "  OpenCTI Offline Deploy — UNPACK + PLACE FILES"
log "══════════════════════════════════════════════════════════════"

# ══════════════════════════════════════════════════════════════
# 1. RPMs — giữ nguyên tại chỗ (chạy install bằng tay sau)
# ══════════════════════════════════════════════════════════════
log ""
log "── RPMs: giữ tại $SCRIPT_DIR/rpms/"
log "  → Chạy tay: cd $SCRIPT_DIR/rpms && bash v2_install_rpms.sh"

# ══════════════════════════════════════════════════════════════
# 2. Runtime tarballs — giữ nguyên (chạy install bằng tay sau)
# ══════════════════════════════════════════════════════════════
log ""
log "── Runtime: giữ tại $SCRIPT_DIR/runtime/"
log "  → Chạy tay: cd $SCRIPT_DIR/runtime && bash v2_install_python.sh && bash v2_install_nodejs.sh"

# ══════════════════════════════════════════════════════════════
# 3. MinIO — binaries + scripts → /usr/local/bin/
# ══════════════════════════════════════════════════════════════
log ""
log "── MinIO → /usr/local/bin/"
cp -f minio/minio /usr/local/bin/minio
cp -f minio/mc    /usr/local/bin/mc
chmod +x /usr/local/bin/minio /usr/local/bin/mc
for f in minio/v2_*.sh; do
    cp -f "$f" "/usr/local/bin/$(basename "$f")"
    chmod +x "/usr/local/bin/$(basename "$f")"
done
log "  ✓ minio, mc, v2_*minio*.sh"
rm -rf minio/
log "  ✓ minio/ cleaned up"

# ══════════════════════════════════════════════════════════════
# 4. RabbitMQ — tarball giữ tại chỗ, scripts → /usr/local/bin/
# ══════════════════════════════════════════════════════════════
log ""
log "── RabbitMQ scripts → /usr/local/bin/"
for f in rabbitmq/v2_start_rabbitmq.sh rabbitmq/v2_stop_rabbitmq.sh rabbitmq/v2_uninstall_rabbitmq.sh; do
    if [[ -f "$f" ]]; then
        cp -f "$f" "/usr/local/bin/$(basename "$f")"
        chmod +x "/usr/local/bin/$(basename "$f")"
    fi
done
log "  ✓ v2_*rabbitmq*.sh"
log "  → Setup tay: cd $SCRIPT_DIR/rabbitmq && bash v2_setup_rabbitmq.sh"

# ══════════════════════════════════════════════════════════════
# 5. Runtime uninstall scripts → /usr/local/bin/
# ══════════════════════════════════════════════════════════════
log ""
log "── Runtime uninstall scripts → /usr/local/bin/"
cp -f runtime/v2_uninstall_python.sh /usr/local/bin/v2_uninstall_python.sh
cp -f runtime/v2_uninstall_nodejs.sh /usr/local/bin/v2_uninstall_nodejs.sh
chmod +x /usr/local/bin/v2_uninstall_*.sh
log "  ✓ v2_uninstall_python.sh, v2_uninstall_nodejs.sh"

# ══════════════════════════════════════════════════════════════
# 6. Config files → /etc/<service>/
# ══════════════════════════════════════════════════════════════
log ""
log "── Config files"

mkdir -p /etc/redis
cp -f config/redis.conf /etc/redis/redis.conf
log "  ✓ /etc/redis/redis.conf"

mkdir -p /etc/minio
cp -f config/minio.conf /etc/minio/minio.conf
log "  ✓ /etc/minio/minio.conf"

mkdir -p /etc/rabbitmq
cp -f config/rabbitmq.conf     /etc/rabbitmq/rabbitmq.conf
cp -f config/rabbitmq-env.conf /etc/rabbitmq/rabbitmq-env.conf
cp -f config/enabled_plugins   /etc/rabbitmq/enabled_plugins
if [[ -f config/90-opencti.conf ]]; then
    mkdir -p /etc/rabbitmq/conf.d
    cp -f config/90-opencti.conf /etc/rabbitmq/conf.d/90-opencti.conf 2>/dev/null || \
    cp -f config/90-opencti.conf /etc/rabbitmq/90-opencti.conf
fi
log "  ✓ /etc/rabbitmq/"

cp -f config/logrotate.conf /etc/logrotate.d/opencti
log "  ✓ /etc/logrotate.d/opencti"

# .env + .env.example → /etc/saids/opencti/
mkdir -p /etc/saids/opencti
if [[ ! -f /etc/saids/opencti/.env ]]; then
    cp -f config/.env /etc/saids/opencti/.env
    log "  ✓ config/.env → /etc/saids/opencti/.env (NEW — kiểm tra credentials!)"
else
    log "  ⏭  /etc/saids/opencti/.env đã tồn tại — giữ nguyên"
fi
cp -f config/.env.example /etc/saids/opencti/.env.example
log "  ✓ config/.env.example → /etc/saids/opencti/.env.example"

rm -rf config/
log "  ✓ config/ cleaned up"

# ══════════════════════════════════════════════════════════════
# 7. Systemd service units → /etc/systemd/system/
# ══════════════════════════════════════════════════════════════
log ""
log "── Systemd services"
cp -f systemd/minio.service             /etc/systemd/system/minio.service
cp -f systemd/rabbitmq.service          /etc/systemd/system/rabbitmq.service
cp -f systemd/opencti-platform.service  /etc/systemd/system/opencti-platform.service
cp -f systemd/opencti-worker@.service   /etc/systemd/system/opencti-worker@.service
systemctl daemon-reload
log "  ✓ 4 services installed + daemon-reload"
rm -rf systemd/
log "  ✓ systemd/ cleaned up"

# ══════════════════════════════════════════════════════════════
# 8. OpenCTI Platform → /etc/saids/opencti/
# ══════════════════════════════════════════════════════════════
log ""
log "── OpenCTI Platform → /etc/saids/opencti/"
rsync -a \
    --exclude='.python-venv' \
    --exclude='logs' \
    --exclude='.support' \
    --exclude='telemetry' \
    --exclude='__pycache__' \
    --exclude='v2_*.sh' \
    --exclude='.env' \
    --exclude='.env.example' \
    opencti/ /etc/saids/opencti/
log "  ✓ Platform files → /etc/saids/opencti/ (không có v2_*.sh, .env)"

# Platform scripts → /usr/local/bin/
cp -f opencti/v2_start_opencti.sh     /usr/local/bin/v2_start_opencti.sh
cp -f opencti/v2_stop_opencti.sh      /usr/local/bin/v2_stop_opencti.sh
cp -f opencti/v2_uninstall_opencti.sh /usr/local/bin/v2_uninstall_opencti.sh
cp -f opencti/v2_setup_opencti.sh     /usr/local/bin/v2_setup_opencti.sh
chmod +x /usr/local/bin/v2_*opencti*.sh
log "  ✓ v2_start/stop/setup/uninstall_opencti.sh → /usr/local/bin/"
rm -rf opencti/
log "  ✓ opencti/ cleaned up"

# ══════════════════════════════════════════════════════════════
# 9. OpenCTI Worker → /etc/saids/opencti-worker/
# ══════════════════════════════════════════════════════════════
log ""
log "── OpenCTI Worker → /etc/saids/opencti-worker/"
mkdir -p /etc/saids/opencti-worker
rsync -a \
    --exclude='.python-venv' \
    --exclude='__pycache__' \
    --exclude='v2_*.sh' \
    opencti-worker/ /etc/saids/opencti-worker/
log "  ✓ Worker files → /etc/saids/opencti-worker/ (không có v2_*.sh)"

# Worker scripts → /usr/local/bin/
cp -f opencti-worker/v2_start_opencti_worker.sh     /usr/local/bin/v2_start_opencti_worker.sh
cp -f opencti-worker/v2_stop_opencti_worker.sh      /usr/local/bin/v2_stop_opencti_worker.sh
cp -f opencti-worker/v2_uninstall_opencti_worker.sh /usr/local/bin/v2_uninstall_opencti_worker.sh
cp -f opencti-worker/v2_setup_opencti_worker.sh     /usr/local/bin/v2_setup_opencti_worker.sh
chmod +x /usr/local/bin/v2_*worker*.sh
log "  ✓ v2_start/stop/setup/uninstall_opencti_worker.sh → /usr/local/bin/"
rm -rf opencti-worker/
log "  ✓ opencti-worker/ cleaned up"

# ══════════════════════════════════════════════════════════════
# 10. Global uninstall script → /usr/local/bin/
# ══════════════════════════════════════════════════════════════
log ""
log "── v2_ti_uninstall_all.sh → /usr/local/bin/"
cp -f v2_ti_uninstall_all.sh /usr/local/bin/v2_ti_uninstall_all.sh
chmod +x /usr/local/bin/v2_ti_uninstall_all.sh
rm -f v2_ti_uninstall_all.sh
log "  ✓ v2_ti_uninstall_all.sh → /usr/local/bin/"

# ══════════════════════════════════════════════════════════════
# Cleanup — xóa unpack script (đã chạy xong)
# ══════════════════════════════════════════════════════════════
rm -f v2_unpack_opencti.sh

# ══════════════════════════════════════════════════════════════
# DONE
# ══════════════════════════════════════════════════════════════
echo ""
log "══════════════════════════════════════════════════════════════"
log "  ✓ FILES PLACED — giờ chạy setup bằng tay"
log "══════════════════════════════════════════════════════════════"
log ""
log "  Còn lại: rpms/ + runtime/ + rabbitmq/ (cần cho setup)"
log ""
log "  # 1. RPMs"
log "  cd $SCRIPT_DIR/rpms && bash v2_install_rpms.sh"
log ""
log "  # 2. Python + Node.js"
log "  cd $SCRIPT_DIR/runtime && bash v2_install_python.sh && bash v2_install_nodejs.sh"
log ""
log "  # 3. MinIO + RabbitMQ setup"
log "  v2_setup_minio.sh"
log "  cd $SCRIPT_DIR/rabbitmq && bash v2_setup_rabbitmq.sh"
log ""
log "  # 4. Start infra"
log "  systemctl enable --now redis minio rabbitmq"
log ""
log "  # 5. Setup OpenCTI venv"
log "  v2_setup_opencti.sh"
log "  v2_setup_opencti_worker.sh"
log ""
log "  # 6. Sửa credentials (QUAN TRỌNG! — 1 file duy nhất)"
log "  vi /etc/saids/opencti/.env"
log ""
log "  # 7. Start OpenCTI"
log "  systemctl enable opencti-platform"
log "  systemctl start opencti-platform"
log "  # Đợi ~60s..."
log "  systemctl enable opencti-worker@{1..3}"
log "  systemctl start opencti-worker@1 opencti-worker@2 opencti-worker@3"
log ""

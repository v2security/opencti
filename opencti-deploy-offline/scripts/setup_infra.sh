#!/bin/bash
###############################################################################
# SETUP INFRASTRUCTURE — First Boot (File Placement Only)
# Target: Rocky Linux 9 (offline deployment)
#
# Script này CHỈ đặt file vào đúng vị trí. KHÔNG start services.
# Sau khi chạy xong, dùng:
#   bash scripts/enable-services.sh      ← Start tất cả + health check
#   hoặc: systemctl enable --now redis minio rabbitmq-server
#
# Components:
#   1. Redis    — In-Memory Store (cài bằng RPM)
#   2. MinIO    — Object Storage  (binary → /usr/local/bin/minio)
#   3. RabbitMQ — Message Broker  (extract → /opt/rabbitmq/, symlinks → /usr/local/bin/)
#
# Config paths (COPY từ config/, KHÔNG auto-generate):
#   /etc/redis/redis.conf            ← Redis config
#   /etc/minio/minio.conf            ← MinIO environment config
#   /etc/rabbitmq/rabbitmq.conf      ← RabbitMQ config
#   /etc/rabbitmq/rabbitmq-env.conf  ← RabbitMQ environment
#   /opt/rabbitmq/etc/rabbitmq/enabled_plugins ← RabbitMQ plugins
#
# Yêu cầu:
#   DEPLOY_DIR/
#   ├── config/
#   │   ├── start.sh              ← Biến env (optional, để đọc password)
#   │   ├── redis.conf            ← Redis config → /etc/redis/
#   │   ├── minio.conf            ← MinIO config → /etc/minio/
#   │   ├── rabbitmq.conf         ← RabbitMQ config → /etc/rabbitmq/
#   │   ├── rabbitmq-env.conf     ← RabbitMQ env → /etc/rabbitmq/
#   │   └── enabled_plugins       ← RabbitMQ plugins → /opt/rabbitmq/etc/rabbitmq/
#   ├── files/
#   │   ├── minio                 ← MinIO binary → /usr/local/bin/minio
#   │   ├── mc                    ← MinIO client → /usr/local/bin/mc (optional)
#   │   └── rabbitmq-server-generic-unix-*.tar.xz ← RabbitMQ tarball
#   ├── rpm/
#   │   ├── redis-*.rpm           ← Redis RPM
#   │   ├── erlang-*.rpm          ← Erlang (for RabbitMQ)
#   │   └── *.rpm                 ← System dependencies
#   ├── scripts/
#   │   ├── run_minio.sh          ← MinIO run script (systemd gọi)
#   │   └── run_rabbitmq.sh       ← RabbitMQ run script (systemd gọi)
#   └── systemd/
#       ├── minio.service
#       └── rabbitmq-server.service
#
# Kết quả sau khi chạy:
#   /usr/local/bin/minio             ← MinIO binary
#   /usr/local/bin/mc                ← MinIO client (if available)
#   /usr/bin/redis-server            ← Redis (from RPM)
#   /opt/rabbitmq/sbin/              ← RabbitMQ binaries
#   /usr/local/bin/rabbitmq-*        ← RabbitMQ symlinks
#   /opt/infra/scripts/run_*.sh      ← Run scripts for MinIO + RabbitMQ
#   /etc/systemd/system/*.service    ← Systemd units (MinIO + RabbitMQ, not started)
#   redis.service                    ← Provided by RPM, already installed
#   /etc/{redis,minio,rabbitmq}/     ← Config files
#   /var/lib/{redis,minio,rabbitmq}/ ← Data directories
#   /var/log/{redis,minio,rabbitmq}/ ← Log directories
#
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="${DEPLOY_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FILES_DIR="$DEPLOY_DIR/files"
RPM_DIR="$DEPLOY_DIR/rpm"
SCRIPTS_SRC="$DEPLOY_DIR/scripts"
SYSTEMD_SRC="$DEPLOY_DIR/systemd"
CONFIG_DIR="$DEPLOY_DIR/config"

INFRA_SCRIPTS_DEST="/opt/infra/scripts"

TOTAL_STEPS=6

# ── Helpers ──────────────────────────────────────────────────
info()   { echo ""; echo "══════════════════════════════════════════════════════════════"; echo "  [STEP $1/$TOTAL_STEPS] $2"; echo "══════════════════════════════════════════════════════════════"; }
detail() { echo "  → $*"; }
ok()     { echo "  ✓ $*"; }
warn()   { echo "  ⚠ $*"; }
die()    { echo "  ✗ $*" >&2; exit 1; }

# ── Pre-checks ───────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Cần chạy với quyền root"
[[ -d "$DEPLOY_DIR" ]] || die "Không tìm thấy $DEPLOY_DIR"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║   SETUP INFRASTRUCTURE — First Boot (File Placement)       ║"
echo "║   Redis (RPM) + MinIO + RabbitMQ                           ║"
echo "║   Target: Rocky Linux 9                                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  Source:   $DEPLOY_DIR"
echo "  Scripts:  $SCRIPTS_SRC"
echo "  Systemd:  $SYSTEMD_SRC"
echo ""

# Verify source files
[[ -f "$FILES_DIR/minio" ]] || die "Missing: $FILES_DIR/minio"
ls "$FILES_DIR"/rabbitmq-server-generic-unix-*.tar.xz &>/dev/null || die "Missing: rabbitmq tarball in $FILES_DIR"
[[ -d "$SCRIPTS_SRC" ]] || die "Missing: $SCRIPTS_SRC"
[[ -d "$SYSTEMD_SRC" ]] || die "Missing: $SYSTEMD_SRC"

# Verify config files
[[ -f "$CONFIG_DIR/redis.conf" ]]    || die "Missing: $CONFIG_DIR/redis.conf"
[[ -f "$CONFIG_DIR/minio.conf" ]]    || die "Missing: $CONFIG_DIR/minio.conf"
[[ -f "$CONFIG_DIR/rabbitmq.conf" ]] || die "Missing: $CONFIG_DIR/rabbitmq.conf"
detail "Config files verified: redis.conf, minio.conf, rabbitmq.conf"

# ══════════════════════════════════════════════════════════════
# STEP 1: Install RPMs (Erlang + system libs + Redis)
# ══════════════════════════════════════════════════════════════
info 1 "Install RPMs (Erlang + system libs + Redis)"

if [[ -d "$RPM_DIR" ]] && ls "$RPM_DIR"/*.rpm &>/dev/null 2>&1; then
    detail "Source: $RPM_DIR/*.rpm"
    cd "$RPM_DIR"
    dnf localinstall -y --allowerasing --nobest --skip-broken *.rpm 2>&1 | tail -5 || \
        rpm -Uvh --force --nodeps *.rpm 2>&1 | tail -5 || true
    ok "RPMs installed ($(ls *.rpm | wc -l) packages)"
else
    warn "No RPM directory found at $RPM_DIR — skipping"
    warn "Redis + RabbitMQ need RPMs! Make sure they are already installed."
fi

# Verify Redis was installed via RPM
if command -v redis-server &>/dev/null; then
    ok "Redis: $(redis-server --version 2>/dev/null || echo 'installed')"
else
    warn "redis-server not found in PATH — RPM có thể thiếu."
    warn "  Cần file rpm/redis-*.rpm trong package."
fi

# ══════════════════════════════════════════════════════════════
# STEP 2: Install MinIO → /usr/local/bin/minio
# ══════════════════════════════════════════════════════════════
info 2 "Install MinIO → /usr/local/bin/minio"

cp "$FILES_DIR/minio" /usr/local/bin/minio && chmod +x /usr/local/bin/minio
ok "MinIO binary → /usr/local/bin/minio"
/usr/local/bin/minio --version 2>/dev/null || true

# Copy mc (MinIO client) if available
if [[ -f "$FILES_DIR/mc" ]]; then
    cp "$FILES_DIR/mc" /usr/local/bin/mc && chmod +x /usr/local/bin/mc
    ok "MinIO client → /usr/local/bin/mc"
fi

# Create directories
mkdir -p /var/lib/minio/data /var/log/minio /etc/minio

# Copy MinIO config → /etc/minio/minio.conf
if [[ ! -f /etc/minio/minio.conf ]]; then
    cp "$CONFIG_DIR/minio.conf" /etc/minio/minio.conf
    chmod 600 /etc/minio/minio.conf
    detail "Copied MinIO config → /etc/minio/minio.conf"
else
    ok "MinIO config already exists → /etc/minio/minio.conf"
fi

# ══════════════════════════════════════════════════════════════
# STEP 3: Install RabbitMQ (extract tarball)
# ══════════════════════════════════════════════════════════════
info 3 "Install RabbitMQ → /opt/rabbitmq/"

if [[ -d /opt/rabbitmq/sbin ]]; then
    ok "RabbitMQ already installed → skip extract"
else
    detail "Extract: rabbitmq-server-generic-unix-*.tar.xz → /opt/rabbitmq/"
    mkdir -p /opt/rabbitmq
    tar -xf "$FILES_DIR"/rabbitmq-server-generic-unix-*.tar.xz \
        --strip-components=1 -C /opt/rabbitmq
fi

mkdir -p /var/lib/rabbitmq/mnesia /var/log/rabbitmq /etc/rabbitmq

# Symlink RabbitMQ binaries → /usr/local/bin/
for bin in /opt/rabbitmq/sbin/*; do
    ln -sf "$bin" /usr/local/bin/"$(basename "$bin")" 2>/dev/null || true
done
ok "RabbitMQ symlinks → /usr/local/bin/"

# Copy RabbitMQ config → /etc/rabbitmq/
if [[ ! -f /etc/rabbitmq/rabbitmq.conf ]]; then
    cp "$CONFIG_DIR/rabbitmq.conf" /etc/rabbitmq/rabbitmq.conf
    detail "Copied RabbitMQ config → /etc/rabbitmq/rabbitmq.conf"
else
    ok "RabbitMQ config already exists → /etc/rabbitmq/rabbitmq.conf"
fi

# Copy RabbitMQ env config
if [[ -f "$CONFIG_DIR/rabbitmq-env.conf" ]] && [[ ! -f /etc/rabbitmq/rabbitmq-env.conf ]]; then
    cp "$CONFIG_DIR/rabbitmq-env.conf" /etc/rabbitmq/rabbitmq-env.conf
    detail "Copied RabbitMQ env → /etc/rabbitmq/rabbitmq-env.conf"
fi

# Copy env config to RabbitMQ's default search path (for CLI tools)
if [[ -f "$CONFIG_DIR/rabbitmq-env.conf" ]]; then
    mkdir -p /opt/rabbitmq/etc/rabbitmq
    cp "$CONFIG_DIR/rabbitmq-env.conf" /opt/rabbitmq/etc/rabbitmq/rabbitmq-env.conf
    detail "Copied RabbitMQ env → /opt/rabbitmq/etc/rabbitmq/rabbitmq-env.conf"
fi

# Copy enabled_plugins
if [[ -f "$CONFIG_DIR/enabled_plugins" ]] && [[ ! -f /opt/rabbitmq/etc/rabbitmq/enabled_plugins ]]; then
    mkdir -p /opt/rabbitmq/etc/rabbitmq
    cp "$CONFIG_DIR/enabled_plugins" /opt/rabbitmq/etc/rabbitmq/enabled_plugins
    detail "Copied enabled_plugins → /opt/rabbitmq/etc/rabbitmq/enabled_plugins"
elif [[ -f /opt/rabbitmq/etc/rabbitmq/enabled_plugins ]]; then
    ok "enabled_plugins already exists"
fi

# Enable management plugin if no enabled_plugins from config
if [[ ! -f /opt/rabbitmq/etc/rabbitmq/enabled_plugins ]]; then
    /opt/rabbitmq/sbin/rabbitmq-plugins enable --offline rabbitmq_management 2>&1 | tail -3 || true
    ok "RabbitMQ management plugin enabled"
fi

ok "RabbitMQ → /opt/rabbitmq"

# ══════════════════════════════════════════════════════════════
# STEP 4: Override Redis config + copy run scripts
# ══════════════════════════════════════════════════════════════
info 4 "Override Redis config + copy run scripts"

# Redis RPM đã tạo /etc/redis/redis.conf, /var/lib/redis, systemd unit.
# Chỉ cần override config bằng bản custom.
if [[ -f "$CONFIG_DIR/redis.conf" ]]; then
    cp -f "$CONFIG_DIR/redis.conf" /etc/redis/redis.conf
    chmod 640 /etc/redis/redis.conf
    detail "Overrode Redis config → /etc/redis/redis.conf"
fi
mkdir -p /var/log/redis
ok "Redis config ready (RPM installed, config overridden)"

# Copy run scripts (MinIO + RabbitMQ only — Redis uses RPM systemd unit)
mkdir -p "$INFRA_SCRIPTS_DEST"

for script in run_minio.sh run_rabbitmq.sh; do
    if [[ -f "$SCRIPTS_SRC/$script" ]]; then
        cp "$SCRIPTS_SRC/$script" "$INFRA_SCRIPTS_DEST/"
        chmod +x "$INFRA_SCRIPTS_DEST/$script"
        ok "$script → $INFRA_SCRIPTS_DEST/$script"
    else
        die "Missing script: $SCRIPTS_SRC/$script"
    fi
done

# ══════════════════════════════════════════════════════════════
# STEP 5: Install systemd services (MinIO + RabbitMQ only)
# ══════════════════════════════════════════════════════════════
info 5 "Install systemd services (MinIO + RabbitMQ)"

# Redis systemd unit đã được cài tự động bởi RPM → không cần copy
for svc in minio.service rabbitmq-server.service; do
    if [[ -f "$SYSTEMD_SRC/$svc" ]]; then
        cp "$SYSTEMD_SRC/$svc" /etc/systemd/system/
        ok "$svc → /etc/systemd/system/$svc"
    else
        die "Missing: $SYSTEMD_SRC/$svc"
    fi
done

ok "redis.service → provided by RPM (already installed)"
systemctl daemon-reload
ok "systemctl daemon-reload done"

# ══════════════════════════════════════════════════════════════
# STEP 6: Summary
# ══════════════════════════════════════════════════════════════
info 6 "Summary"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║       INFRASTRUCTURE SETUP COMPLETE (Files Only)           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  📁 Binaries:"
echo "    /usr/local/bin/minio             MinIO server"
if [[ -x /usr/local/bin/mc ]]; then
echo "    /usr/local/bin/mc                MinIO client"
fi
if command -v redis-server &>/dev/null; then
echo "    $(command -v redis-server)        Redis (RPM)"
fi
echo "    /opt/rabbitmq/sbin/              RabbitMQ"
echo "    /usr/local/bin/rabbitmq-*        RabbitMQ symlinks"
echo ""
echo "  📁 Config Files:"
echo "    /etc/redis/redis.conf            Redis config"
echo "    /etc/minio/minio.conf            MinIO config"
echo "    /etc/rabbitmq/rabbitmq.conf      RabbitMQ config"
echo "    /etc/rabbitmq/rabbitmq-env.conf  RabbitMQ environment"
echo ""
echo "  📁 Data Directories:"
echo "    /var/lib/redis/                  Redis data"
echo "    /var/lib/minio/data/             MinIO data"
echo "    /var/lib/rabbitmq/mnesia/        RabbitMQ data"
echo ""
echo "  📁 Log Directories:"
echo "    /var/log/redis/                  Redis logs"
echo "    /var/log/minio/                  MinIO logs"
echo "    /var/log/rabbitmq/               RabbitMQ logs"
echo ""
echo "  📁 Systemd (NOT started yet):"
echo "    redis.service                     (from RPM)"
echo "    /etc/systemd/system/minio.service"
echo "    /etc/systemd/system/rabbitmq-server.service"
echo ""
echo "  ⚠  Services chưa được start!"
echo "  👉 Bước tiếp: bash scripts/enable-services.sh"
echo "     hoặc:      systemctl enable --now redis minio rabbitmq-server"
echo "     status:    systemctl status redis minio rabbitmq-server"
echo ""

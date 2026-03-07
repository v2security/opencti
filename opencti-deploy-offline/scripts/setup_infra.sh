#!/bin/bash
###############################################################################
# SETUP INFRASTRUCTURE — MinIO + Redis + RabbitMQ
# Target: Rocky Linux 9 (offline deployment)
#
# Script này cài đặt và khởi động 3 infrastructure services:
#   1. MinIO    — Object Storage  (binary từ files/minio)
#   2. Redis    — In-Memory Store (compile từ files/redis-*.tar.gz)
#   3. RabbitMQ — Message Broker  (extract từ files/rabbitmq-server-*.tar.xz)
#
# Biến lấy từ config/start.sh (nếu có):
#   REDIS__PORT, REDIS__PASSWORD
#   MINIO__ACCESS_KEY, MINIO__SECRET_KEY, MINIO__BUCKET_NAME
#   RABBITMQ__USERNAME, RABBITMQ__PASSWORD
#
# Config paths:
#   /etc/minio/minio.conf          — MinIO environment config   (COPY từ config/)
#   /etc/redis/redis.conf          — Redis config               (COPY từ config/)
#   /etc/rabbitmq/rabbitmq.conf    — RabbitMQ config            (COPY từ config/)
#   /etc/rabbitmq/rabbitmq-env.conf — RabbitMQ environment      (COPY từ config/)
#   /opt/rabbitmq/etc/rabbitmq/enabled_plugins — RabbitMQ plugins (COPY từ config/)
#
# Log paths:
#   /var/log/minio/                — MinIO logs (via systemd)
#   /var/log/redis/redis.log       — Redis logs (via logfile directive)
#   /var/log/rabbitmq/             — RabbitMQ logs (native)
#
# Cách dùng:
#   bash setup_infra.sh
#
# Yêu cầu:
#   DEPLOY_DIR/
#   ├── config/
#   │   ├── start.sh                              ← Biến env (optional)
#   │   ├── redis.conf                            ← Redis config → /etc/redis/
#   │   ├── minio.conf                            ← MinIO config → /etc/minio/
#   │   ├── rabbitmq.conf                         ← RabbitMQ config → /etc/rabbitmq/
#   │   ├── rabbitmq-env.conf                     ← RabbitMQ env → /etc/rabbitmq/
#   │   └── enabled_plugins                       ← RabbitMQ plugins → /opt/rabbitmq/etc/rabbitmq/
#   ├── files/
#   │   ├── minio                                  ← MinIO binary
#   │   ├── redis-8.4.2.tar.gz                     ← Redis source
#   │   └── rabbitmq-server-generic-unix-4.2.0.tar.xz ← RabbitMQ
#   ├── rpm/
#   │   ├── erlang-*.rpm                           ← Erlang (for RabbitMQ)
#   │   └── *.rpm                                  ← System dependencies
#   └── infra/
#       ├── scripts/
#       │   ├── run_minio.sh
#       │   ├── run_redis.sh
#       │   └── run_rabbitmq.sh
#       ├── systemd/
#       │   ├── minio.service
#       │   ├── redis.service
#       │   └── rabbitmq-server.service
#       └── setup_infra.sh                         ← This file
#
# Kết quả sau khi chạy:
#   /opt/minio/bin/minio           ← MinIO binary
#   /opt/redis/bin/redis-server    ← Redis (compiled)
#   /opt/rabbitmq/sbin/            ← RabbitMQ binaries
#   /opt/infra/scripts/run_*.sh    ← Run scripts (systemd gọi)
#   /etc/systemd/system/*.service  ← Systemd units
#   /etc/minio/minio.conf          ← MinIO config  (COPY từ config/)
#   /etc/redis/redis.conf          ← Redis config  (COPY từ config/)
#   /etc/rabbitmq/rabbitmq.conf    ← RabbitMQ config (COPY từ config/)
#   /etc/rabbitmq/rabbitmq-env.conf ← RabbitMQ env  (COPY từ config/)
#   /var/log/{minio,redis,rabbitmq}/ ← Log directories
#
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="${DEPLOY_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FILES_DIR="$DEPLOY_DIR/files"
RPM_DIR="$DEPLOY_DIR/rpm"
SCRIPTS_SRC="$DEPLOY_DIR/scripts"
SYSTEMD_SRC="$DEPLOY_DIR/systemd"
START_SH="$DEPLOY_DIR/config/start.sh"

INFRA_SCRIPTS_DEST="/opt/infra/scripts"

TOTAL_STEPS=8

# ── Helpers ──────────────────────────────────────────────────
info()   { echo ""; echo "══════════════════════════════════════════════════════════════"; echo "  [STEP $1/$TOTAL_STEPS] $2"; echo "══════════════════════════════════════════════════════════════"; }
detail() { echo "  → $*"; }
ok()     { echo "  ✓ $*"; }
warn()   { echo "  ⚠ $*"; }
die()    { echo "  ✗ $*" >&2; exit 1; }

wait_for() {
    local name=$1 cmd=$2 t=${3:-30}
    echo -n "  ⏳ Waiting for $name"
    for _ in $(seq 1 "$t"); do
        eval "$cmd" &>/dev/null && { echo ""; ok "$name ready"; return 0; }
        echo -n "."
        sleep 1
    done
    echo ""
    warn "$name not ready after ${t}s"
    return 1
}

# ── Pre-checks ───────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Cần chạy với quyền root"
[[ -d "$DEPLOY_DIR" ]] || die "Không tìm thấy $DEPLOY_DIR"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║   SETUP INFRASTRUCTURE — MinIO + Redis + RabbitMQ          ║"
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
ls "$FILES_DIR"/redis-*.tar.gz &>/dev/null || die "Missing: redis tarball in $FILES_DIR"
[[ -d "$SCRIPTS_SRC" ]] || die "Missing: $SCRIPTS_SRC"
[[ -d "$SYSTEMD_SRC" ]] || die "Missing: $SYSTEMD_SRC"

# Verify config files (KHÔNG auto-generate, phải có sẵn)
CONFIG_DIR="$DEPLOY_DIR/config"
[[ -f "$CONFIG_DIR/redis.conf" ]]    || die "Missing: $CONFIG_DIR/redis.conf"
[[ -f "$CONFIG_DIR/minio.conf" ]]    || die "Missing: $CONFIG_DIR/minio.conf"
[[ -f "$CONFIG_DIR/rabbitmq.conf" ]] || die "Missing: $CONFIG_DIR/rabbitmq.conf"
detail "Config files verified: redis.conf, minio.conf, rabbitmq.conf"

# ══════════════════════════════════════════════════════════════
# STEP 1: Load variables from start.sh
# ══════════════════════════════════════════════════════════════
info 1 "Load variables from start.sh"

if [[ -f "$START_SH" ]]; then
    detail "Source: $START_SH"
    # Chỉ lấy các biến REDIS__, MINIO__, RABBITMQ__ — không chạy exec ở cuối
    eval "$(grep -E '^export (REDIS__|MINIO__|RABBITMQ__)' "$START_SH")"
    ok "Variables loaded from start.sh"
else
    warn "start.sh not found at $START_SH — using defaults"
fi

# Map biến OpenCTI → biến infrastructure
INFRA_REDIS_PORT="${REDIS__PORT:-6379}"
INFRA_REDIS_PASSWORD="${REDIS__PASSWORD:-Vipstmt@828682}"

INFRA_MINIO_ACCESS_KEY="${MINIO__ACCESS_KEY:-opencti}"
INFRA_MINIO_SECRET_KEY="${MINIO__SECRET_KEY:-Vipstmt@828682}"
INFRA_MINIO_BUCKET="${MINIO__BUCKET_NAME:-opencti-bucket}"

INFRA_RABBITMQ_USER="${RABBITMQ__USERNAME:-opencti}"
INFRA_RABBITMQ_PASSWORD="${RABBITMQ__PASSWORD:-Vipstmt@828682}"

detail "Redis:    port=$INFRA_REDIS_PORT, password=****"
detail "MinIO:    user=$INFRA_MINIO_ACCESS_KEY, bucket=$INFRA_MINIO_BUCKET"
detail "RabbitMQ: user=$INFRA_RABBITMQ_USER"

# ══════════════════════════════════════════════════════════════
# STEP 2: Install RPM dependencies (Erlang, system libs)
# ══════════════════════════════════════════════════════════════
info 2 "Install RPM dependencies (Erlang + system libs)"
if [[ -d "$RPM_DIR" ]] && ls "$RPM_DIR"/*.rpm &>/dev/null 2>&1; then
    detail "Source: $RPM_DIR/*.rpm"
    cd "$RPM_DIR"
    dnf localinstall -y --allowerasing *.rpm 2>&1 | tail -3 || \
        rpm -Uvh --force --nodeps *.rpm 2>&1 | tail -3 || true
    ok "RPMs installed ($(ls *.rpm | wc -l) packages)"
else
    warn "No RPM directory found at $RPM_DIR — skipping"
    warn "RabbitMQ needs Erlang! Make sure Erlang is already installed."
fi

# ══════════════════════════════════════════════════════════════
# STEP 3: Install MinIO (binary copy)
# ══════════════════════════════════════════════════════════════
info 3 "Install MinIO"
detail "Source: $FILES_DIR/minio → /opt/minio/bin/minio"
mkdir -p /opt/minio/bin /var/lib/minio/data /var/log/minio /etc/minio

cp "$FILES_DIR/minio" /opt/minio/bin/ && chmod +x /opt/minio/bin/minio

# Copy mc (MinIO client) if available
if [[ -f "$FILES_DIR/mc" ]]; then
    cp "$FILES_DIR/mc" /usr/local/bin/ && chmod +x /usr/local/bin/mc
    ok "MinIO client (mc) → /usr/local/bin/mc"
fi

# Copy MinIO config → /etc/minio/minio.conf (từ config/, KHÔNG generate)
if [[ ! -f /etc/minio/minio.conf ]]; then
    cp "$CONFIG_DIR/minio.conf" /etc/minio/minio.conf
    chmod 600 /etc/minio/minio.conf
    detail "Copied MinIO config → /etc/minio/minio.conf"
else
    ok "MinIO config already exists → /etc/minio/minio.conf"
fi

/opt/minio/bin/minio --version 2>/dev/null || true
ok "MinIO → /opt/minio/bin/minio"

# ══════════════════════════════════════════════════════════════
# STEP 4: Install RabbitMQ (extract tarball)
# ══════════════════════════════════════════════════════════════
info 4 "Install RabbitMQ"
if [[ -d /opt/rabbitmq/sbin ]]; then
    ok "RabbitMQ already installed → skip extract"
else
    detail "Extract: rabbitmq-server-generic-unix-*.tar.xz → /opt/rabbitmq/"
    mkdir -p /opt/rabbitmq
    tar -xf "$FILES_DIR"/rabbitmq-server-generic-unix-*.tar.xz \
        --strip-components=1 -C /opt/rabbitmq
fi

mkdir -p /var/lib/rabbitmq/mnesia /var/log/rabbitmq /etc/rabbitmq

# Symlink RabbitMQ binaries
for bin in /opt/rabbitmq/sbin/*; do
    ln -sf "$bin" /usr/local/bin/"$(basename "$bin")" 2>/dev/null || true
done

# Copy RabbitMQ config → /etc/rabbitmq/rabbitmq.conf (từ config/, KHÔNG generate)
if [[ ! -f /etc/rabbitmq/rabbitmq.conf ]]; then
    cp "$CONFIG_DIR/rabbitmq.conf" /etc/rabbitmq/rabbitmq.conf
    detail "Copied RabbitMQ config → /etc/rabbitmq/rabbitmq.conf"
else
    ok "RabbitMQ config already exists → /etc/rabbitmq/rabbitmq.conf"
fi

# Copy RabbitMQ env config if available
if [[ -f "$CONFIG_DIR/rabbitmq-env.conf" ]] && [[ ! -f /etc/rabbitmq/rabbitmq-env.conf ]]; then
    cp "$CONFIG_DIR/rabbitmq-env.conf" /etc/rabbitmq/rabbitmq-env.conf
    detail "Copied RabbitMQ env → /etc/rabbitmq/rabbitmq-env.conf"
fi

# CRITICAL: Also copy env config to RabbitMQ's default config search path
# Generic-unix CLI tools (rabbitmqctl, etc.) look for rabbitmq-env.conf at
# /opt/rabbitmq/etc/rabbitmq/ — without this, CLI tools won't find NODENAME
# and will default to rabbit@$(hostname) instead of rabbit@localhost
if [[ -f "$CONFIG_DIR/rabbitmq-env.conf" ]]; then
    mkdir -p /opt/rabbitmq/etc/rabbitmq
    cp "$CONFIG_DIR/rabbitmq-env.conf" /opt/rabbitmq/etc/rabbitmq/rabbitmq-env.conf
    detail "Copied RabbitMQ env → /opt/rabbitmq/etc/rabbitmq/rabbitmq-env.conf (for CLI tools)"
fi

# Copy enabled_plugins if available and not already in place (e.g. mounted)
if [[ -f "$CONFIG_DIR/enabled_plugins" ]] && [[ ! -f /opt/rabbitmq/etc/rabbitmq/enabled_plugins ]]; then
    mkdir -p /opt/rabbitmq/etc/rabbitmq
    cp "$CONFIG_DIR/enabled_plugins" /opt/rabbitmq/etc/rabbitmq/enabled_plugins
    detail "Copied enabled_plugins → /opt/rabbitmq/etc/rabbitmq/enabled_plugins"
elif [[ -f /opt/rabbitmq/etc/rabbitmq/enabled_plugins ]]; then
    ok "enabled_plugins already exists → /opt/rabbitmq/etc/rabbitmq/enabled_plugins"
fi

# Enable management plugin (nếu chưa có enabled_plugins từ config/)
if [[ ! -f /opt/rabbitmq/etc/rabbitmq/enabled_plugins ]]; then
    detail "Enabling rabbitmq_management plugin (offline)..."
    /opt/rabbitmq/sbin/rabbitmq-plugins enable --offline rabbitmq_management 2>&1 | tail -3 || true
    ok "RabbitMQ management plugin enabled"
else
    ok "RabbitMQ enabled_plugins already configured (from config/)"
fi

ok "RabbitMQ → /opt/rabbitmq"

# ══════════════════════════════════════════════════════════════
# STEP 5: Install Redis (compile from source)
# ══════════════════════════════════════════════════════════════
info 5 "Install Redis (compile from source)"
if [[ -x /opt/redis/bin/redis-server ]]; then
    ok "Redis already compiled → skip"
    /opt/redis/bin/redis-server --version 2>/dev/null || true
else
    REDIS_TARBALL=$(ls "$FILES_DIR"/redis-*.tar.gz 2>/dev/null | head -1)
    if [[ -n "$REDIS_TARBALL" ]]; then
        detail "Source: $(basename "$REDIS_TARBALL")"

        # Check build tools (Redis 8.x cần g++ cho fast_float)
        if ! command -v make &>/dev/null || ! command -v gcc &>/dev/null; then
            die "Redis compilation needs 'gcc', 'g++' and 'make'. Install them first or use Redis RPM."
        fi
        if ! command -v g++ &>/dev/null; then
            die "Redis 8.x needs 'g++' (gcc-c++ package) for fast_float library."
        fi

        detail "Extracting..."
        cd /tmp
        rm -rf /tmp/redis-*
        tar -xzf "$REDIS_TARBALL"
        REDIS_SRC=$(ls -d /tmp/redis-* 2>/dev/null | head -1)

        if [[ -z "$REDIS_SRC" || ! -d "$REDIS_SRC" ]]; then
            die "Failed to extract Redis source"
        fi

        detail "Compiling Redis (this may take 1-2 minutes)..."
        cd "$REDIS_SRC"
        make -j"$(nproc)" 2>&1 | tail -5
        make install PREFIX=/opt/redis 2>&1 | tail -3

        # Cleanup source — MUST cd out first, otherwise cwd is deleted
        # and subsequent commands (e.g. rabbitmqctl) fail silently
        cd /tmp
        rm -rf "$REDIS_SRC"

        /opt/redis/bin/redis-server --version
        ok "Redis compiled → /opt/redis/bin/redis-server"
    else
        # Fallback: check if system redis-server exists (from RPM)
        if command -v redis-server &>/dev/null; then
            ok "Using system redis-server: $(redis-server --version)"
        else
            die "No Redis source tarball and no system redis-server found"
        fi
    fi
fi

# Create Redis directories + symlinks
mkdir -p /var/lib/redis /etc/redis /var/log/redis
if [[ -x /opt/redis/bin/redis-server ]]; then
    ln -sf /opt/redis/bin/redis-server /usr/local/bin/redis-server 2>/dev/null || true
    ln -sf /opt/redis/bin/redis-cli /usr/local/bin/redis-cli 2>/dev/null || true
fi

# Copy Redis config → /etc/redis/redis.conf (từ config/, KHÔNG generate)
if [[ ! -f /etc/redis/redis.conf ]]; then
    cp "$CONFIG_DIR/redis.conf" /etc/redis/redis.conf
    chmod 640 /etc/redis/redis.conf
    detail "Copied Redis config → /etc/redis/redis.conf"
else
    ok "Redis config already exists → /etc/redis/redis.conf"
fi

# ══════════════════════════════════════════════════════════════
# STEP 6: Copy run scripts
# ══════════════════════════════════════════════════════════════
info 6 "Copy run scripts → $INFRA_SCRIPTS_DEST"
mkdir -p "$INFRA_SCRIPTS_DEST"

for script in run_minio.sh run_redis.sh run_rabbitmq.sh; do
    if [[ -f "$SCRIPTS_SRC/$script" ]]; then
        cp "$SCRIPTS_SRC/$script" "$INFRA_SCRIPTS_DEST/"
        chmod +x "$INFRA_SCRIPTS_DEST/$script"
        ok "$script → $INFRA_SCRIPTS_DEST/$script"
    else
        die "Missing script: $SCRIPTS_SRC/$script"
    fi
done

# ══════════════════════════════════════════════════════════════
# STEP 7: Install systemd services
# ══════════════════════════════════════════════════════════════
info 7 "Install systemd services"

for svc in minio.service redis.service rabbitmq-server.service; do
    if [[ -f "$SYSTEMD_SRC/$svc" ]]; then
        cp "$SYSTEMD_SRC/$svc" /etc/systemd/system/
        ok "$svc → /etc/systemd/system/$svc"
    else
        die "Missing: $SYSTEMD_SRC/$svc"
    fi
done

systemctl daemon-reload
ok "systemctl daemon-reload done"

# ══════════════════════════════════════════════════════════════
# STEP 8: Enable and start all services
# ══════════════════════════════════════════════════════════════
info 8 "Enable and start all services"

for svc in redis minio rabbitmq-server; do
    detail "Starting $svc..."
    systemctl enable "$svc" 2>/dev/null || true
    systemctl start "$svc" 2>/dev/null || true
    sleep 2

    STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "failed")
    if [[ "$STATUS" == "active" ]]; then
        ok "$svc: $STATUS"
    else
        warn "$svc: $STATUS"
        warn "  → Check logs: journalctl -u $svc -n 30 --no-pager"
        # Show last few lines of journal for debugging
        journalctl -u "$svc" -n 10 --no-pager 2>/dev/null || true
    fi
done

# ── Health checks ────────────────────────────────────────────
echo ""
echo "  📊 Health checks:"

# Redis: dùng password từ start.sh
REDIS_AUTH_ARGS=""
if [[ -n "$INFRA_REDIS_PASSWORD" ]]; then
    REDIS_AUTH_ARGS="-a $INFRA_REDIS_PASSWORD --no-auth-warning"
fi
wait_for "Redis (localhost:$INFRA_REDIS_PORT)" \
    "redis-cli -p $INFRA_REDIS_PORT $REDIS_AUTH_ARGS ping 2>/dev/null | grep -q PONG" 15 || true

wait_for "MinIO (localhost:9000)" \
    "curl -sf http://localhost:9000/minio/health/live" 15 || true

wait_for "RabbitMQ (localhost:5672)" \
    "RABBITMQ_CONF_ENV_FILE=/etc/rabbitmq/rabbitmq-env.conf rabbitmqctl status 2>/dev/null" 60 || true

# ── RabbitMQ: Create user + vhost (dùng biến từ start.sh) ────
if RABBITMQ_CONF_ENV_FILE=/etc/rabbitmq/rabbitmq-env.conf rabbitmqctl status &>/dev/null; then
    detail "Configuring RabbitMQ user and permissions..."
    detail "  User: $INFRA_RABBITMQ_USER (from start.sh RABBITMQ__USERNAME)"
    RABBITMQ_CONF_ENV_FILE=/etc/rabbitmq/rabbitmq-env.conf rabbitmqctl add_user "$INFRA_RABBITMQ_USER" "$INFRA_RABBITMQ_PASSWORD" 2>/dev/null || \
        RABBITMQ_CONF_ENV_FILE=/etc/rabbitmq/rabbitmq-env.conf rabbitmqctl change_password "$INFRA_RABBITMQ_USER" "$INFRA_RABBITMQ_PASSWORD" 2>/dev/null || true
    RABBITMQ_CONF_ENV_FILE=/etc/rabbitmq/rabbitmq-env.conf rabbitmqctl set_user_tags "$INFRA_RABBITMQ_USER" administrator 2>/dev/null || true
    RABBITMQ_CONF_ENV_FILE=/etc/rabbitmq/rabbitmq-env.conf rabbitmqctl set_permissions -p / "$INFRA_RABBITMQ_USER" ".*" ".*" ".*" 2>/dev/null || true
    ok "RabbitMQ user '$INFRA_RABBITMQ_USER' configured (admin)"
else
    warn "RabbitMQ not running — skipping user creation"
fi

# ── MinIO: Create bucket (dùng biến từ start.sh) ────────────
if curl -sf http://localhost:9000/minio/health/live &>/dev/null && command -v mc &>/dev/null; then
    detail "Configuring MinIO bucket..."
    detail "  Bucket: $INFRA_MINIO_BUCKET (from start.sh MINIO__BUCKET_NAME)"
    mc alias set local http://localhost:9000 "$INFRA_MINIO_ACCESS_KEY" "$INFRA_MINIO_SECRET_KEY" 2>/dev/null || true
    mc mb "local/$INFRA_MINIO_BUCKET" 2>/dev/null || true
    ok "MinIO bucket '$INFRA_MINIO_BUCKET' created"
else
    warn "MinIO not ready or mc not found — skipping bucket creation"
fi

# ══════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          INFRASTRUCTURE SETUP COMPLETE                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  📊 Service Status:"
for svc in redis minio rabbitmq-server; do
    STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
    if [[ "$STATUS" == "active" ]]; then
        printf "    ✅ %-20s %s\n" "$svc" "$STATUS"
    else
        printf "    ❌ %-20s %s\n" "$svc" "$STATUS"
    fi
done
echo ""
echo "  🌐 Ports:"
echo "    Redis:             $INFRA_REDIS_PORT"
echo "    MinIO API:         9000"
echo "    MinIO Console:     9001"
echo "    RabbitMQ AMQP:     5672"
echo "    RabbitMQ Mgmt:     15672"
echo ""
echo "  📁 Config Files:"
echo "    /etc/minio/minio.conf          MinIO config"
echo "    /etc/redis/redis.conf          Redis config"
echo "    /etc/rabbitmq/rabbitmq.conf    RabbitMQ config"
echo ""
echo "  📁 Log Directories:"
echo "    /var/log/minio/                MinIO logs"
echo "    /var/log/redis/                Redis logs"
echo "    /var/log/rabbitmq/             RabbitMQ logs"
echo ""
echo "  📁 Binaries:"
echo "    /opt/minio/bin/minio           MinIO binary"
echo "    /opt/redis/bin/redis-server    Redis (compiled)"
echo "    /opt/rabbitmq/sbin/            RabbitMQ binaries"
echo "    /opt/infra/scripts/run_*.sh    Run scripts"
echo "    /etc/systemd/system/*.service  Systemd units"
echo ""
echo "  🔧 Commands:"
echo "    systemctl status  {redis,minio,rabbitmq-server}"
echo "    systemctl restart {redis,minio,rabbitmq-server}"
echo "    tail -f /var/log/redis/redis.log"
echo "    tail -f /var/log/minio/minio.log"
echo "    tail -f /var/log/rabbitmq/*.log"
echo ""

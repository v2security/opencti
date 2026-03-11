#!/bin/bash
###############################################################################
# ENABLE SERVICES — Start all services + health checks + post-config
# Target: Rocky Linux 9 (offline deployment)
#
# Chạy AFTER setup_infra.sh + setup_app.sh (first-boot scripts).
# Script này CHỈ enable, start services và configure post-start tasks.
#
# Phần 1 — Infrastructure:
#   • Redis       — enable + start + PING check
#   • MinIO       — enable + start + health check + create bucket
#   • RabbitMQ    — enable + start + status check + create user
#
# Phần 2 — Application:
#   • Elasticsearch — health check (phải running sẵn)
#   • OpenCTI Platform — enable + start + wait API ready
#   • OpenCTI Worker   — enable + start N instances
#
# Flags:
#   --infra-only    Chỉ start infrastructure services
#   --app-only      Chỉ start application services
#   --skip-app      Giống --infra-only
#   --workers=N     Số lượng worker instances (default: 3)
#
# Cách dùng:
#   bash enable-services.sh                # Start tất cả
#   bash enable-services.sh --infra-only   # Chỉ infra
#   bash enable-services.sh --app-only     # Chỉ app
#   bash enable-services.sh --workers=5    # 5 worker instances
#
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="${DEPLOY_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CONFIG_DIR="$DEPLOY_DIR/config"
START_SH="$CONFIG_DIR/start.sh"

# ── Defaults ─────────────────────────────────────────────────
INFRA_ONLY=false
APP_ONLY=false
WORKER_COUNT=3

for arg in "$@"; do
    case "$arg" in
        --infra-only|--skip-app) INFRA_ONLY=true ;;
        --app-only)              APP_ONLY=true ;;
        --workers=*)             WORKER_COUNT="${arg#--workers=}" ;;
        --help|-h)
            echo "Usage: $0 [--infra-only] [--app-only] [--workers=N]"
            exit 0 ;;
    esac
done

# ── Helpers ──────────────────────────────────────────────────
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

start_svc() {
    local svc=$1
    detail "Enable + start $svc..."
    systemctl enable "$svc" 2>/dev/null || true
    systemctl start "$svc" 2>/dev/null || true
    sleep 2
    STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "failed")
    if [[ "$STATUS" == "active" ]]; then
        ok "$svc: $STATUS"
    else
        warn "$svc: $STATUS"
        warn "  → journalctl -u $svc -n 20 --no-pager"
        journalctl -u "$svc" -n 5 --no-pager 2>/dev/null || true
    fi
}

# ── Pre-checks ───────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Cần chạy với quyền root"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║   ENABLE SERVICES — Start + Health Check + Post-config     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# ── Load variables from start.sh (for passwords) ────────────
INFRA_REDIS_PORT=6379
INFRA_REDIS_PASSWORD=""
INFRA_MINIO_ACCESS_KEY="opencti"
INFRA_MINIO_SECRET_KEY=""
INFRA_MINIO_BUCKET="opencti-bucket"
INFRA_RABBITMQ_USER="opencti"
INFRA_RABBITMQ_PASSWORD=""

if [[ -f "$START_SH" ]]; then
    eval "$(grep -E '^export (REDIS__|MINIO__|RABBITMQ__)' "$START_SH")" 2>/dev/null || true
    INFRA_REDIS_PORT="${REDIS__PORT:-6379}"
    INFRA_REDIS_PASSWORD="${REDIS__PASSWORD:-}"
    INFRA_MINIO_ACCESS_KEY="${MINIO__ACCESS_KEY:-opencti}"
    INFRA_MINIO_SECRET_KEY="${MINIO__SECRET_KEY:-}"
    INFRA_MINIO_BUCKET="${MINIO__BUCKET_NAME:-opencti-bucket}"
    INFRA_RABBITMQ_USER="${RABBITMQ__USERNAME:-opencti}"
    INFRA_RABBITMQ_PASSWORD="${RABBITMQ__PASSWORD:-}"
fi

# ══════════════════════════════════════════════════════════════
#  PART 1 — INFRASTRUCTURE
# ══════════════════════════════════════════════════════════════
if [[ "$APP_ONLY" != "true" ]]; then
    echo ""
    echo "  ── Infrastructure Services ──────────────────────────────"

    # ── Redis ────────────────────────────────────────────────
    start_svc redis

    REDIS_AUTH_ARGS=""
    if [[ -n "$INFRA_REDIS_PASSWORD" ]]; then
        REDIS_AUTH_ARGS="-a $INFRA_REDIS_PASSWORD --no-auth-warning"
    fi
    wait_for "Redis PING" \
        "redis-cli -p $INFRA_REDIS_PORT $REDIS_AUTH_ARGS ping 2>/dev/null | grep -q PONG" 15 || true

    # ── MinIO ────────────────────────────────────────────────
    start_svc minio

    wait_for "MinIO health" \
        "curl -sf http://localhost:9000/minio/health/live" 15 || true

    # Create bucket
    if curl -sf http://localhost:9000/minio/health/live &>/dev/null && command -v mc &>/dev/null; then
        detail "Configuring MinIO bucket: $INFRA_MINIO_BUCKET"
        mc alias set local http://localhost:9000 "$INFRA_MINIO_ACCESS_KEY" "$INFRA_MINIO_SECRET_KEY" 2>/dev/null || true
        mc mb "local/$INFRA_MINIO_BUCKET" 2>/dev/null || true
        ok "MinIO bucket '$INFRA_MINIO_BUCKET' ready"
    fi

    # ── RabbitMQ ─────────────────────────────────────────────
    start_svc rabbitmq-server

    wait_for "RabbitMQ" \
        "RABBITMQ_CONF_ENV_FILE=/etc/rabbitmq/rabbitmq-env.conf rabbitmqctl status 2>/dev/null" 60 || true

    # Create user + permissions
    if RABBITMQ_CONF_ENV_FILE=/etc/rabbitmq/rabbitmq-env.conf rabbitmqctl status &>/dev/null; then
        detail "Configuring RabbitMQ user: $INFRA_RABBITMQ_USER"
        RABBITMQ_CONF_ENV_FILE=/etc/rabbitmq/rabbitmq-env.conf rabbitmqctl add_user "$INFRA_RABBITMQ_USER" "$INFRA_RABBITMQ_PASSWORD" 2>/dev/null || \
            RABBITMQ_CONF_ENV_FILE=/etc/rabbitmq/rabbitmq-env.conf rabbitmqctl change_password "$INFRA_RABBITMQ_USER" "$INFRA_RABBITMQ_PASSWORD" 2>/dev/null || true
        RABBITMQ_CONF_ENV_FILE=/etc/rabbitmq/rabbitmq-env.conf rabbitmqctl set_user_tags "$INFRA_RABBITMQ_USER" administrator 2>/dev/null || true
        RABBITMQ_CONF_ENV_FILE=/etc/rabbitmq/rabbitmq-env.conf rabbitmqctl set_permissions -p / "$INFRA_RABBITMQ_USER" ".*" ".*" ".*" 2>/dev/null || true
        ok "RabbitMQ user '$INFRA_RABBITMQ_USER' configured (admin)"
    else
        warn "RabbitMQ not running — skipping user creation"
    fi
fi

# ══════════════════════════════════════════════════════════════
#  PART 2 — APPLICATION
# ══════════════════════════════════════════════════════════════
if [[ "$INFRA_ONLY" != "true" ]]; then
    echo ""
    echo "  ── Application Services ─────────────────────────────────"

    # ── Check infrastructure health ──────────────────────────
    detail "Checking infrastructure..."

    REDIS_PASS=$(grep -oP '(?<=^requirepass ).*' /etc/redis/redis.conf 2>/dev/null || true)
    if command -v redis-cli &>/dev/null; then
        redis-cli -p 6379 ${REDIS_PASS:+-a "$REDIS_PASS" --no-auth-warning} ping 2>/dev/null | grep -q PONG \
            && ok "Redis: PONG" || warn "Redis: not responding"
    fi

    curl -sf http://localhost:9000/minio/health/live &>/dev/null \
        && ok "MinIO: healthy" || warn "MinIO: not responding"

    ES_URL=$(grep -oP '(?<=ELASTICSEARCH__URL=")[^"]*' /etc/saids/opencti/start.sh 2>/dev/null \
          || grep -oP '(?<=ELASTICSEARCH__URL=")[^"]*' "$START_SH" 2>/dev/null \
          || echo "http://localhost:9200")
    curl -sf "${ES_URL:-http://localhost:9200}" &>/dev/null \
        && ok "Elasticsearch: healthy (${ES_URL})" || warn "Elasticsearch: not responding (${ES_URL})"

    RABBITMQ_CONF_ENV_FILE=/etc/rabbitmq/rabbitmq-env.conf rabbitmqctl status &>/dev/null \
        && ok "RabbitMQ: running" || warn "RabbitMQ: not responding"

    # ── OpenCTI Platform ─────────────────────────────────────
    start_svc opencti-platform
    sleep 3

    detail "Waiting for OpenCTI API..."
    wait_for "OpenCTI API" \
        "curl -skf https://localhost:8443/health 2>/dev/null || curl -skf http://localhost:8443/health 2>/dev/null" \
        120 || warn "Platform API not ready — starting workers anyway"

    # ── OpenCTI Workers ──────────────────────────────────────
    detail "Starting $WORKER_COUNT worker instances..."
    for i in $(seq 1 "$WORKER_COUNT"); do
        systemctl enable "opencti-worker@${i}" 2>/dev/null || true
        systemctl start  "opencti-worker@${i}" 2>/dev/null || true
    done
    sleep 2

    for i in $(seq 1 "$WORKER_COUNT"); do
        STATUS=$(systemctl is-active "opencti-worker@${i}" 2>/dev/null || echo "failed")
        if [[ "$STATUS" == "active" ]]; then
            ok "opencti-worker@${i}: $STATUS"
        else
            warn "opencti-worker@${i}: $STATUS"
        fi
    done
fi

# ══════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║             ALL SERVICES ENABLED                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  📊 Service Status:"
for svc in redis minio rabbitmq-server opencti-platform; do
    STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
    if [[ "$STATUS" == "active" ]]; then
        printf "    ✅ %-24s %s\n" "$svc" "$STATUS"
    else
        printf "    ⚠️  %-24s %s\n" "$svc" "$STATUS"
    fi
done
for i in $(seq 1 "$WORKER_COUNT"); do
    STATUS=$(systemctl is-active "opencti-worker@${i}" 2>/dev/null || echo "inactive")
    if [[ "$STATUS" == "active" ]]; then
        printf "    ✅ %-24s %s\n" "opencti-worker@${i}" "$STATUS"
    else
        printf "    ⚠️  %-24s %s\n" "opencti-worker@${i}" "$STATUS"
    fi
done
echo ""
echo "  🌐 Access:"
echo "    Platform:   https://localhost:8443"
echo "    MinIO:      http://localhost:9001"
echo "    RabbitMQ:   http://localhost:15672"
echo ""
echo "  🔧 Commands:"
echo "    systemctl status  redis minio rabbitmq-server"
echo "    systemctl status  opencti-platform opencti-worker@{1..$WORKER_COUNT}"
echo "    journalctl -u opencti-platform -f"
echo ""

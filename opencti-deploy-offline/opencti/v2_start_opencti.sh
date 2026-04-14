#!/bin/bash
###############################################################################
# v2_start_opencti.sh — Start OpenCTI Platform
#
# Chạy TRONG container/bare-metal.
# Mount to: /usr/local/bin/v2_start_opencti.sh
# Called by: systemd (opencti-platform.service) ExecStart
#
# Đọc config tập trung từ /etc/saids/opencti/.env
# rồi map sang biến OpenCTI (APP__*) và exec npm run serv.
###############################################################################
set -euo pipefail

# ── Shared config ────────────────────────────────────────────
ENV_FILE="${OPENCTI_ENV_FILE:-/etc/saids/opencti/.env}"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
else
    echo "[ERROR] Config file not found: $ENV_FILE" >&2
    exit 1
fi

# ── Python 3.12 (compiled with --enable-shared) + Node.js 22 (pre-built) ──
export LD_LIBRARY_PATH="/opt/python312/lib:${LD_LIBRARY_PATH:-}"
export PATH="/opt/nodejs/bin:/opt/python312/bin:/etc/saids/opencti/.python-venv/bin:$PATH"
export PYTHONPATH="/etc/saids/opencti/.python-venv/lib/python3.12/site-packages"
export PYTHONUNBUFFERED=1
export PYTHONDONTWRITEBYTECODE=1

# ── Node.js Runtime ──────────────────────────────────────────
export NODE_ENV=production
export NODE_OPTIONS="--max-old-space-size=8096"

# ── Map flat env vars → OpenCTI nested format (APP__*) ──────
export APP__PORT="${APP_PORT:-8080}"
export APP__BASE_URL="${APP_BASE_URL:-http://localhost:8080/}"
export APP__HTTPS_CERT__REJECT_UNAUTHORIZED="${APP_HTTPS_CERT_REJECT_UNAUTHORIZED:-false}"
export APP__ADMIN__EMAIL="${APP_ADMIN_EMAIL:-admin@v2secure.vn}"
export APP__ADMIN__PASSWORD="${APP_ADMIN_PASSWORD}"
export APP__ADMIN__TOKEN="${APP_ADMIN_TOKEN}"
export APP__HEALTH_ACCESS_KEY="${APP_HEALTH_ACCESS_KEY:-}"

# ── Redis ────────────────────────────────────────────────────
export REDIS__HOSTNAME="${REDIS_HOSTNAME:-localhost}"
export REDIS__PORT="${REDIS_PORT:-6379}"
export REDIS__PASSWORD="${REDIS_PASSWORD}"

# ── Elasticsearch ────────────────────────────────────────────
export ELASTICSEARCH__URL="${ELASTICSEARCH_URL:-http://localhost:8686}"
export ELASTICSEARCH__NUMBER_OF_REPLICAS="${ELASTICSEARCH_NUMBER_OF_REPLICAS:-0}"

# ── MinIO (S3) ───────────────────────────────────────────────
export MINIO__ENDPOINT="${MINIO_ENDPOINT:-localhost}"
export MINIO__PORT="${MINIO_PORT:-9000}"
export MINIO__USE_SSL="${MINIO_USE_SSL:-false}"
export MINIO__ACCESS_KEY="${MINIO_ACCESS_KEY:-opencti}"
export MINIO__SECRET_KEY="${MINIO_SECRET_KEY}"
export MINIO__BUCKET_NAME="${MINIO_BUCKET_NAME:-opencti-bucket}"

# ── RabbitMQ ─────────────────────────────────────────────────
export RABBITMQ__HOSTNAME="${RABBITMQ_HOSTNAME:-localhost}"
export RABBITMQ__PORT="${RABBITMQ_PORT:-5672}"
export RABBITMQ__PORT_MANAGEMENT="${RABBITMQ_PORT_MANAGEMENT:-15672}"
export RABBITMQ__MANAGEMENT_SSL="${RABBITMQ_MANAGEMENT_SSL:-false}"
export RABBITMQ__USERNAME="${RABBITMQ_USERNAME:-opencti}"
export RABBITMQ__PASSWORD="${RABBITMQ_PASSWORD}"

# ── SMTP ─────────────────────────────────────────────────────
export SMTP__HOSTNAME="${SMTP_HOSTNAME:-localhost}"
export SMTP__PORT="${SMTP_PORT:-25}"

# ── Authentication ───────────────────────────────────────────
export PROVIDERS__LOCAL__STRATEGY="LocalStrategy"

# ── AI Configuration ─────────────────────────────────────────
export AI__ENABLED="${AI_ENABLED:-false}"
export AI__TYPE="${AI_TYPE:-openai}"
export AI__ENDPOINT="${AI_ENDPOINT:-}"
export AI__TOKEN="${AI_TOKEN:-}"
export AI__MODEL="${AI_MODEL:-}"
export AI__MODEL_IMAGES="${AI_MODEL_IMAGES:-}"
export AI__MAX_TOKENS="${AI_MAX_TOKENS:-8192}"
export AI__TIMEOUT="${AI_TIMEOUT:-60000}"

# ── Chatbot Configuration ────────────────────────────────────
export CHATBOT__ENABLED="${CHATBOT_ENABLED:-true}"
export CHATBOT__TYPE="${CHATBOT_TYPE:-openai}"
export CHATBOT__ENDPOINT="${CHATBOT_ENDPOINT:-}"
export CHATBOT__TOKEN="${CHATBOT_TOKEN:-}"
export CHATBOT__MODEL="${CHATBOT_MODEL:-}"
export CHATBOT__MAX_TOKENS="${CHATBOT_MAX_TOKENS:-4096}"

# ── Start ────────────────────────────────────────────────────
cd /etc/saids/opencti
exec npm run serv
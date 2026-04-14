#!/bin/bash
###############################################################################
# v2_start_opencti_worker.sh — Start OpenCTI Worker
#
# Chạy TRONG container/bare-metal.
# Mount to: /usr/local/bin/v2_start_opencti_worker.sh
# Called by: systemd (opencti-worker@.service) ExecStart
#
# Đọc config tập trung từ /etc/saids/opencti/.env
# Biến phải khớp với Platform:
#   OPENCTI_URL  = APP_BASE_URL
#   OPENCTI_TOKEN = APP_ADMIN_TOKEN
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

# ── Python 3.12 (compiled, --enable-shared) ──────────────────
export LD_LIBRARY_PATH="/opt/python312/lib:${LD_LIBRARY_PATH:-}"
export PATH="/opt/python312/bin:/etc/saids/opencti-worker/.python-venv/bin:$PATH"
export PYTHONPATH="/etc/saids/opencti-worker/.python-venv/lib/python3.12/site-packages"
export PYTHONUNBUFFERED=1
export PYTHONDONTWRITEBYTECODE=1

# ── OpenCTI Connection (derived from shared .env) ───────────
export OPENCTI_URL="${APP_BASE_URL:-http://localhost:8080}"
export OPENCTI_TOKEN="${APP_ADMIN_TOKEN}"
export OPENCTI_JSON_LOGGING="true"

# ── Worker Configuration ─────────────────────────────────────
export WORKER_LOG_LEVEL="${WORKER_LOG_LEVEL:-info}"
export WORKER_TELEMETRY_ENABLED="${WORKER_TELEMETRY_ENABLED:-false}"

# ── Execution Pool ───────────────────────────────────────────
export OPENCTI_EXECUTION_POOL_SIZE="${OPENCTI_EXECUTION_POOL_SIZE:-2}"
export OPENCTI_REALTIME_EXECUTION_POOL_SIZE="${OPENCTI_REALTIME_EXECUTION_POOL_SIZE:-3}"
export WORKER_LISTEN_POOL_SIZE="${WORKER_LISTEN_POOL_SIZE:-5}"

# ── Start ────────────────────────────────────────────────────
cd /etc/saids/opencti-worker/src
exec python3 worker.py

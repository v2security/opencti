#!/bin/bash
###############################################################################
# SETUP APP — Deploy OpenCTI Platform + Worker (Part 2)
# Target: Rocky Linux 9 (offline deployment)
#
# Script này deploy TOÀN BỘ phần ứng dụng từ pre-built package:
#   • Python 3.12 runtime (compiled, --enable-shared) → /opt/python312
#   • Node.js 22 runtime (pre-built binary)           → /opt/nodejs
#   • OpenCTI Platform (backend + frontend) → /etc/saids/application/opencti
#   • OpenCTI Worker (Python)               → /etc/saids/application/opencti-worker
#   • Python venvs + offline pip packages
#   • Systemd services
#   • SSL certificates
#
# Prerequisites (Part 1 phải chạy trước):
#   - Elasticsearch đang chạy
#   - Redis đang chạy (port 6379)
#   - MinIO đang chạy (port 9000)
#   - RabbitMQ đang chạy (port 5672)
#
# Input:
#   DEPLOY_DIR/
#   ├── files/
#   │   └── opencti-app-package.tar.gz  ← Từ pack_app.sh
#   ├── config/
#   │   ├── start.sh                    ← Platform env vars + start command
#   │   └── start-worker.sh             ← Worker env vars + start command
#   ├── cert/
#   │   ├── opencti.key                 ← SSL private key
#   │   └── opencti.crt                 ← SSL certificate
#   └── systemd/
#       ├── opencti-platform.service
#       └── opencti-worker@.service
#
# Cách dùng:
#   bash setup_app.sh                     # Full deploy + start
#   bash setup_app.sh --skip-worker       # Chỉ deploy platform
#   bash setup_app.sh --skip-start        # Deploy nhưng không start
#
# Kết quả:
#   /opt/python312/                        ← Python 3.12 runtime
#   /opt/nodejs/                           ← Node.js 22 runtime
#   /etc/saids/application/opencti/        ← Platform install
#   /etc/saids/application/opencti-worker/ ← Worker install
#   /var/log/application/opencti/          ← Platform logs
#   /var/log/application/opencti-worker/   ← Worker logs
#   /etc/systemd/system/opencti-platform.service
#   /etc/systemd/system/opencti-worker@.service
#
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="${DEPLOY_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FILES_DIR="$DEPLOY_DIR/files"
CONFIG_DIR="$DEPLOY_DIR/config"
CERT_DIR="$DEPLOY_DIR/cert"
SYSTEMD_SRC="$DEPLOY_DIR/systemd"

# Install paths
PYTHON_HOME="/opt/python312"
NODEJS_HOME="/opt/nodejs"
OPENCTI_HOME="/etc/saids/application/opencti"
WORKER_HOME="/etc/saids/application/opencti-worker"
OPENCTI_LOG="/var/log/application/opencti"
WORKER_LOG="/var/log/application/opencti-worker"

PACKAGE="$FILES_DIR/opencti-app-package.tar.gz"
TEMP_EXTRACT="/tmp/opencti-app-extract"

TOTAL_STEPS=8

# ── Parse flags ──────────────────────────────────────────────
SKIP_WORKER=false
SKIP_START=false
for arg in "$@"; do
    case "$arg" in
        --skip-worker) SKIP_WORKER=true ;;
        --skip-start)  SKIP_START=true ;;
        --help|-h)
            echo "Usage: $0 [--skip-worker] [--skip-start]"
            echo "  --skip-worker  Chỉ deploy platform, bỏ qua worker"
            echo "  --skip-start   Deploy nhưng không start services"
            exit 0 ;;
    esac
done

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
echo "║   SETUP APP — Part 2: Source Code + Môi trường             ║"
echo "║   Target: Rocky Linux 9 (offline)                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  Source:    $DEPLOY_DIR"
echo "  Package:   $PACKAGE"
echo "  Python:    $PYTHON_HOME"
echo "  Node.js:   $NODEJS_HOME"
echo "  Platform:  $OPENCTI_HOME"
echo "  Worker:    $WORKER_HOME"
echo ""

# Verify package
[[ -f "$PACKAGE" ]] || die "Missing: $PACKAGE (chạy pack_app.sh trên máy build trước)"
[[ -f "$CONFIG_DIR/start.sh" ]] || die "Missing: $CONFIG_DIR/start.sh"

# ══════════════════════════════════════════════════════════════
# STEP 1: Extract package
# ══════════════════════════════════════════════════════════════
info 1 "Extract app package"

rm -rf "$TEMP_EXTRACT"
mkdir -p "$TEMP_EXTRACT"
detail "Extracting $(basename "$PACKAGE")..."
tar -xzf "$PACKAGE" -C "$TEMP_EXTRACT"

# Verify expected structure
[[ -d "$TEMP_EXTRACT/runtimes/python312" ]] || die "Package missing: runtimes/python312/"
[[ -d "$TEMP_EXTRACT/runtimes/nodejs" ]]    || die "Package missing: runtimes/nodejs/"
[[ -d "$TEMP_EXTRACT/platform" ]]           || die "Package missing: platform/"
ok "Package extracted → $TEMP_EXTRACT"

# ══════════════════════════════════════════════════════════════
# STEP 2: Install Python 3.12 Runtime
# ══════════════════════════════════════════════════════════════
info 2 "Install Python 3.12 Runtime → $PYTHON_HOME"

if [[ -x "$PYTHON_HOME/bin/python3.12" ]]; then
    PY_VER=$("$PYTHON_HOME/bin/python3.12" --version 2>/dev/null || echo "unknown")
    ok "Python already installed: $PY_VER → skip"
else
    detail "Copying Python 3.12 runtime..."
    rm -rf "$PYTHON_HOME"
    mkdir -p /opt
    cp -a "$TEMP_EXTRACT/runtimes/python312" "$PYTHON_HOME"
    chmod +x "$PYTHON_HOME/bin/python3.12"
    PY_VER=$("$PYTHON_HOME/bin/python3.12" --version 2>/dev/null || echo "unknown")
    ok "Python installed: $PY_VER"
fi

# Verify shared library
if ls "$PYTHON_HOME/lib/libpython3.12"*.so* &>/dev/null; then
    ok "Shared library: $(ls "$PYTHON_HOME"/lib/libpython3.12*.so* | head -1)"
else
    warn "libpython3.12.so not found — Python may not work correctly"
fi

# ══════════════════════════════════════════════════════════════
# STEP 3: Install Node.js 22 Runtime (pre-built binary)
# ══════════════════════════════════════════════════════════════
info 3 "Install Node.js 22 Runtime → $NODEJS_HOME"

if [[ -x "$NODEJS_HOME/bin/node" ]]; then
    NODE_VER=$("$NODEJS_HOME/bin/node" -v 2>/dev/null || echo "unknown")
    ok "Node.js already installed: $NODE_VER → skip"
else
    detail "Copying Node.js 22 pre-built binary..."
    rm -rf "$NODEJS_HOME"
    mkdir -p /opt
    cp -a "$TEMP_EXTRACT/runtimes/nodejs" "$NODEJS_HOME"
    chmod +x "$NODEJS_HOME/bin/node"
    NODE_VER=$("$NODEJS_HOME/bin/node" -v 2>/dev/null || echo "unknown")
    ok "Node.js installed: $NODE_VER"
fi

# Create symlinks
ln -sf "$NODEJS_HOME/bin/node" /usr/bin/node 2>/dev/null || true
ln -sf "$NODEJS_HOME/bin/npm"  /usr/bin/npm  2>/dev/null || true
ln -sf "$NODEJS_HOME/bin/npx"  /usr/bin/npx  2>/dev/null || true

# Set environment for current script
export LD_LIBRARY_PATH="$PYTHON_HOME/lib:${LD_LIBRARY_PATH:-}"
export PATH="$NODEJS_HOME/bin:$PYTHON_HOME/bin:$PATH"

NPM_VER=$(npm -v 2>/dev/null || echo "not found")
detail "npm: $NPM_VER"

# ══════════════════════════════════════════════════════════════
# STEP 4: Deploy OpenCTI Platform + Worker
# ══════════════════════════════════════════════════════════════
info 4 "Deploy OpenCTI Platform + Worker"

# Create directories
mkdir -p "$OPENCTI_HOME" "$WORKER_HOME" "$OPENCTI_LOG" "$WORKER_LOG"

# Deploy platform
detail "Copying platform → $OPENCTI_HOME"
cp -a "$TEMP_EXTRACT/platform/." "$OPENCTI_HOME/"
[[ -f "$OPENCTI_HOME/build/back.js" ]] || die "Missing: $OPENCTI_HOME/build/back.js"
ok "Platform → $OPENCTI_HOME"

# Create required directories
install -m 0777 -d "$OPENCTI_HOME/logs" 2>/dev/null || true
install -m 0777 -d "$OPENCTI_HOME/telemetry" 2>/dev/null || true
install -m 0777 -d "$OPENCTI_HOME/.support" 2>/dev/null || true

# Deploy worker
if [[ "$SKIP_WORKER" == "false" ]]; then
    if [[ -d "$TEMP_EXTRACT/worker" ]]; then
        detail "Copying worker → $WORKER_HOME"
        cp -a "$TEMP_EXTRACT/worker/." "$WORKER_HOME/"
        ok "Worker → $WORKER_HOME"
    else
        warn "Package missing worker/ directory — skipping"
    fi
fi

# ══════════════════════════════════════════════════════════════
# STEP 5: Setup Python virtual environments + install packages
# ══════════════════════════════════════════════════════════════
info 5 "Setup Python environments"

PYTHON_BIN="$PYTHON_HOME/bin/python3.12"

# ── Platform Python venv ──────────────────────────────────────
detail "Creating platform venv → $OPENCTI_HOME/.python-venv"
"$PYTHON_BIN" -m venv "$OPENCTI_HOME/.python-venv" 2>/dev/null || \
    "$PYTHON_BIN" -m venv --without-pip "$OPENCTI_HOME/.python-venv"

PLATFORM_PIP="$OPENCTI_HOME/.python-venv/bin/pip"
PLATFORM_PYTHON="$OPENCTI_HOME/.python-venv/bin/python3"

# Ensure pip in venv
if [[ ! -x "$PLATFORM_PIP" ]]; then
    "$PLATFORM_PYTHON" -m ensurepip 2>/dev/null || true
fi

# Install platform Python deps
PLATFORM_REQS="$OPENCTI_HOME/src/python/requirements.txt"
PLATFORM_PYPACKAGES="$TEMP_EXTRACT/python-packages/platform"

if [[ -d "$PLATFORM_PYPACKAGES" ]] && ls "$PLATFORM_PYPACKAGES"/*.whl &>/dev/null 2>&1; then
    detail "Installing platform Python packages (offline)..."
    "$PLATFORM_PIP" install --no-index --find-links="$PLATFORM_PYPACKAGES" \
        -r "$PLATFORM_REQS" 2>&1 | tail -5 || warn "Some packages failed"
    "$PLATFORM_PIP" install --no-index --find-links="$PLATFORM_PYPACKAGES" \
        pycti 2>&1 | tail -3 || true
    ok "Platform Python packages installed (offline)"
elif [[ -f "$PLATFORM_REQS" ]]; then
    detail "Installing platform Python packages (from requirements.txt)..."
    "$PLATFORM_PIP" install -r "$PLATFORM_REQS" 2>&1 | tail -5 || warn "Some packages failed"
    if [[ -d "$TEMP_EXTRACT/client-python" ]]; then
        "$PLATFORM_PIP" install "$TEMP_EXTRACT/client-python" 2>&1 | tail -3 || true
    fi
    ok "Platform Python packages installed"
else
    warn "No platform Python requirements found"
fi

# ── Worker Python venv ────────────────────────────────────────
if [[ "$SKIP_WORKER" == "false" ]]; then
    detail "Creating worker venv → $WORKER_HOME/.python-venv"
    "$PYTHON_BIN" -m venv "$WORKER_HOME/.python-venv" 2>/dev/null || \
        "$PYTHON_BIN" -m venv --without-pip "$WORKER_HOME/.python-venv"

    WORKER_PIP="$WORKER_HOME/.python-venv/bin/pip"
    WORKER_PYTHON="$WORKER_HOME/.python-venv/bin/python3"

    if [[ ! -x "$WORKER_PIP" ]]; then
        "$WORKER_PYTHON" -m ensurepip 2>/dev/null || true
    fi

    WORKER_REQS="$WORKER_HOME/src/requirements.txt"
    WORKER_PYPACKAGES="$TEMP_EXTRACT/python-packages/worker"

    if [[ -d "$WORKER_PYPACKAGES" ]] && ls "$WORKER_PYPACKAGES"/*.whl &>/dev/null 2>&1; then
        detail "Installing worker Python packages (offline)..."
        "$WORKER_PIP" install --no-index --find-links="$WORKER_PYPACKAGES" \
            -r "$WORKER_REQS" 2>&1 | tail -5 || warn "Some packages failed"
        "$WORKER_PIP" install --no-index --find-links="$WORKER_PYPACKAGES" \
            pycti pika pyyaml 2>&1 | tail -3 || true
        ok "Worker Python packages installed (offline)"
    elif [[ -f "$WORKER_REQS" ]]; then
        detail "Installing worker Python packages (from requirements.txt)..."
        "$WORKER_PIP" install -r "$WORKER_REQS" 2>&1 | tail -5 || warn "Some packages failed"
        if [[ -d "$TEMP_EXTRACT/client-python" ]]; then
            "$WORKER_PIP" install "$TEMP_EXTRACT/client-python" 2>&1 | tail -3 || true
        fi
        "$WORKER_PIP" install pika pyyaml 2>&1 | tail -3 || true
        ok "Worker Python packages installed"
    else
        warn "No worker Python requirements found"
    fi
fi

# Cleanup temp extract
rm -rf "$TEMP_EXTRACT"

# ══════════════════════════════════════════════════════════════
# STEP 6: Copy SSL certificates + config files
# ══════════════════════════════════════════════════════════════
info 6 "Copy SSL certificates + config files"

# SSL
SSL_DIR="$OPENCTI_HOME/ssl"
mkdir -p "$SSL_DIR"

if [[ -f "$CERT_DIR/opencti.key" ]] && [[ -f "$CERT_DIR/opencti.crt" ]]; then
    cp "$CERT_DIR/opencti.key" "$SSL_DIR/opencti.key"
    cp "$CERT_DIR/opencti.crt" "$SSL_DIR/opencti.crt"
    chmod 600 "$SSL_DIR/opencti.key"
    chmod 644 "$SSL_DIR/opencti.crt"
    ok "SSL: $SSL_DIR/opencti.key, $SSL_DIR/opencti.crt"
else
    warn "SSL certificates not found in $CERT_DIR"
    warn "  Generate with: bash scripts/gen-ssl-cert.sh"
fi

# Platform start.sh
if [[ -f "$CONFIG_DIR/start.sh" ]]; then
    cp "$CONFIG_DIR/start.sh" "$OPENCTI_HOME/start.sh"
    chmod +x "$OPENCTI_HOME/start.sh"
    ok "Platform: $OPENCTI_HOME/start.sh"
fi

# Worker start-worker.sh
if [[ "$SKIP_WORKER" == "false" ]]; then
    if [[ -f "$CONFIG_DIR/start-worker.sh" ]]; then
        cp "$CONFIG_DIR/start-worker.sh" "$WORKER_HOME/start-worker.sh"
        chmod +x "$WORKER_HOME/start-worker.sh"
        ok "Worker: $WORKER_HOME/start-worker.sh"
    else
        warn "Missing: $CONFIG_DIR/start-worker.sh — creating default"
        cat > "$WORKER_HOME/start-worker.sh" <<'WORKEREOF'
#!/bin/bash
set -euo pipefail
export LD_LIBRARY_PATH="/opt/python312/lib:${LD_LIBRARY_PATH:-}"
export PATH="/opt/python312/bin:/etc/saids/application/opencti-worker/.python-venv/bin:$PATH"
export PYTHONUNBUFFERED=1
export OPENCTI_URL="https://localhost:8443"
export OPENCTI_TOKEN="f2de8e60-4914-4f69-a42f-6e0c70a72c30"
export OPENCTI_SSL_VERIFY="false"
export WORKER_LOG_LEVEL="info"
cd /etc/saids/application/opencti-worker/src
exec python3 worker.py
WORKEREOF
        chmod +x "$WORKER_HOME/start-worker.sh"
        ok "Worker: $WORKER_HOME/start-worker.sh (default created)"
    fi
fi

# Sysctl tuning
if [[ -f "$CONFIG_DIR/90-opencti.conf" ]]; then
    mkdir -p /etc/sysctl.d
    cp "$CONFIG_DIR/90-opencti.conf" /etc/sysctl.d/90-opencti.conf
    sysctl --system 2>/dev/null | tail -3 || true
    ok "Sysctl: /etc/sysctl.d/90-opencti.conf"
fi

# Logrotate
if [[ -f "$CONFIG_DIR/opencti-logrotate.conf" ]]; then
    cp "$CONFIG_DIR/opencti-logrotate.conf" /etc/logrotate.d/opencti
    ok "Logrotate: /etc/logrotate.d/opencti"
fi

# ══════════════════════════════════════════════════════════════
# STEP 7: Install systemd services
# ══════════════════════════════════════════════════════════════
info 7 "Install systemd services"

# Platform service
if [[ -f "$SYSTEMD_SRC/opencti-platform.service" ]]; then
    cp "$SYSTEMD_SRC/opencti-platform.service" /etc/systemd/system/
    ok "opencti-platform.service → /etc/systemd/system/"
else
    warn "Missing: $SYSTEMD_SRC/opencti-platform.service"
fi

# Worker template unit
if [[ "$SKIP_WORKER" == "false" ]] && [[ -f "$SYSTEMD_SRC/opencti-worker@.service" ]]; then
    cp "$SYSTEMD_SRC/opencti-worker@.service" /etc/systemd/system/
    ok "opencti-worker@.service → /etc/systemd/system/"
fi

systemctl daemon-reload
ok "systemctl daemon-reload done"

# ══════════════════════════════════════════════════════════════
# STEP 8: Enable and start services
# ══════════════════════════════════════════════════════════════
info 8 "Enable and start services"

# Check infrastructure first
detail "Checking infrastructure services..."

# Redis
REDIS_PASS=$(grep -oP '(?<=^requirepass ).*' /etc/redis/redis.conf 2>/dev/null || true)
if command -v redis-cli &>/dev/null; then
    redis-cli -p 6379 ${REDIS_PASS:+-a "$REDIS_PASS" --no-auth-warning} ping 2>/dev/null | grep -q PONG \
        && ok "Redis: PONG" || warn "Redis: not responding"
fi

curl -sf http://localhost:9000/minio/health/live &>/dev/null \
    && ok "MinIO: healthy" || warn "MinIO: not responding"

ES_URL=$(grep -oP '(?<=ELASTICSEARCH__URL=")[^"]*' "$CONFIG_DIR/start.sh" 2>/dev/null || echo "http://localhost:9200")
curl -sf "${ES_URL:-http://localhost:9200}" &>/dev/null \
    && ok "Elasticsearch: healthy" || warn "Elasticsearch: not responding"

RABBITMQ_CONF_ENV_FILE=/etc/rabbitmq/rabbitmq-env.conf rabbitmqctl status &>/dev/null \
    && ok "RabbitMQ: running" || warn "RabbitMQ: not responding"

if [[ "$SKIP_START" == "true" ]]; then
    detail "SKIPPED (--skip-start)"
    detail "Manually start with:"
    detail "  systemctl start opencti-platform"
    detail "  systemctl start opencti-worker@{1..3}"
else
    # Start platform
    detail "Starting opencti-platform..."
    systemctl enable opencti-platform 2>/dev/null || true
    systemctl start opencti-platform 2>/dev/null || true
    sleep 3

    STATUS=$(systemctl is-active opencti-platform 2>/dev/null || echo "failed")
    if [[ "$STATUS" == "active" ]]; then
        ok "opencti-platform: $STATUS"
    else
        warn "opencti-platform: $STATUS"
        warn "  → Check logs: journalctl -u opencti-platform -n 30 --no-pager"
        journalctl -u opencti-platform -n 10 --no-pager 2>/dev/null || true
    fi

    # Start worker instances
    if [[ "$SKIP_WORKER" == "false" ]]; then
        detail "Waiting for platform API..."
        wait_for "OpenCTI API" \
            "curl -skf https://localhost:8443/health 2>/dev/null || curl -skf http://localhost:8443/health 2>/dev/null" \
            120 || warn "Platform API not ready — starting workers anyway"

        WORKER_COUNT=${WORKER_COUNT:-3}
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
fi

# ══════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          SETUP APP COMPLETE (Part 2)                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  🐍 Python:   $("$PYTHON_HOME/bin/python3.12" --version 2>/dev/null || echo 'N/A')"
echo "  📗 Node.js:  $("$NODEJS_HOME/bin/node" -v 2>/dev/null || echo 'N/A')"
echo ""
echo "  📊 Service Status:"
for svc in opencti-platform opencti-worker@1 opencti-worker@2 opencti-worker@3; do
    STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
    if [[ "$STATUS" == "active" ]]; then
        printf "    ✅ %-22s %s\n" "$svc" "$STATUS"
    else
        printf "    ⚠️  %-22s %s\n" "$svc" "$STATUS"
    fi
done
echo ""
echo "  📁 Install Directories:"
echo "    $PYTHON_HOME      Python 3.12 runtime"
echo "    $NODEJS_HOME      Node.js 22 runtime"
echo "    $OPENCTI_HOME     Platform"
echo "    $WORKER_HOME      Worker"
echo ""
echo "  📁 Logs:"
echo "    $OPENCTI_LOG"
echo "    $WORKER_LOG"
echo ""
echo "  🌐 Access:"
echo "    Platform:   https://localhost:8443"
echo "    Admin:      admin@v2secure.vn"
echo ""
echo "  🔧 Commands:"
echo "    systemctl status  opencti-platform opencti-worker@{1..3}"
echo "    systemctl restart opencti-platform"
echo "    systemctl restart opencti-worker@{1..3}"
echo "    journalctl -u opencti-platform -f"
echo "    journalctl -u opencti-worker@1 -f"
echo ""

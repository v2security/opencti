#!/bin/bash
###############################################################################
# v2_prepare_opencti_worker.sh — Chuẩn bị source OpenCTI Worker cho offline deploy
#
# Chạy TRÊN HOST (trước khi docker compose up hoặc copy sang bare-metal).
# Copy worker source + pip packages từ repo vào thư mục opencti-worker/
# (deploy folder) sẵn sàng mount/copy vào target.
#
# Prerequisites:
#   - runtime/python312.tar.gz có sẵn (Python 3.12 portable)
#
# Usage:
#   cd opencti-deploy-offline/opencti-worker
#   ./v2_prepare_opencti_worker.sh
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR"                                           # opencti-deploy-offline/opencti-worker/
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"                       # repo root (parent of opencti-deploy-offline)
OFFLINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"                        # opencti-deploy-offline/
WORKER_SRC="$REPO_ROOT/opencti-worker"

log()   { echo -e "\e[32m[PREPARE-WORKER]\e[0m $1"; }
warn()  { echo -e "\e[33m[PREPARE-WORKER]\e[0m $1"; }
error() { echo -e "\e[31m[PREPARE-WORKER]\e[0m $1" >&2; exit 1; }

# Cleanup function for temp Python
cleanup_python() {
    if [[ -n "${PY312_TMP:-}" && -d "${PY312_TMP:-}" ]]; then
        log "Cleaning up temp Python 3.12..."
        rm -rf "$PY312_TMP"
    fi
}

# ══════════════════════════════════════════════════════════════
# CHECKS
# ══════════════════════════════════════════════════════════════
[[ -d "$WORKER_SRC/src" ]]              || error "Worker src/ not found at $WORKER_SRC"
[[ -f "$WORKER_SRC/src/worker.py" ]]    || error "worker.py not found at $WORKER_SRC/src/"
[[ -f "$OFFLINE_DIR/runtime/python312.tar.gz" ]] || error "runtime/python312.tar.gz not found!"

# ══════════════════════════════════════════════════════════════
# EXTRACT PYTHON 3.12 (dùng để download pip packages đúng ABI cp312)
# ══════════════════════════════════════════════════════════════
PY312_TMP="$(mktemp -d /tmp/py312-prepare-XXXXXX)"
trap cleanup_python EXIT
log "Extracting Python 3.12 → $PY312_TMP ..."
tar xzf "$OFFLINE_DIR/runtime/python312.tar.gz" -C "$PY312_TMP"
PY312="$PY312_TMP/python312/bin/python3.12"
export LD_LIBRARY_PATH="$PY312_TMP/python312/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

[[ -x "$PY312" ]] || error "Python 3.12 binary not found after extraction!"
log "  Python: $($PY312 --version)"
# pip3.12 shebang hardcoded to /opt/python312 — always use python3.12 -m pip
PIP312="$PY312 -m pip"

log "══════════════════════════════════════════════════════════════"
log "  Preparing OpenCTI Worker deployment"
log "══════════════════════════════════════════════════════════════"
log "  Repo:   $REPO_ROOT"
log "  Deploy: $DEPLOY_DIR"
log ""

# ══════════════════════════════════════════════════════════════
# COPY WORKER SOURCE
# ══════════════════════════════════════════════════════════════
log "Syncing worker src/..."
rsync -a --delete \
    --exclude='__pycache__' \
    "$WORKER_SRC/src/" "$DEPLOY_DIR/src/"

# ══════════════════════════════════════════════════════════════
# DOWNLOAD PIP PACKAGES (offline install later)
# Dùng Python 3.12 từ runtime → pip download sẽ resolve đúng cp312
# ══════════════════════════════════════════════════════════════
log "Downloading pip packages for worker (via Python 3.12)..."
mkdir -p "$DEPLOY_DIR/.pip-packages"

if [[ -f "$WORKER_SRC/src/requirements.txt" ]]; then
    $PIP312 download \
        -r "$WORKER_SRC/src/requirements.txt" \
        -d "$DEPLOY_DIR/.pip-packages" \
        --quiet 2>/dev/null || warn "Some pip packages failed to download"
else
    warn "requirements.txt not found at $WORKER_SRC/src/"
fi
log "  ✓ $(ls "$DEPLOY_DIR/.pip-packages/" | wc -l) packages ready"

log ""
log "══════════════════════════════════════════════════════════════"
log "  ✓ Worker deployment READY"
log "══════════════════════════════════════════════════════════════"
log "  Deploy dir: $DEPLOY_DIR"
log ""
log "  Contents prepared:"
log "    src/, .pip-packages/"
log ""
log "  Next: docker compose up -d  (hoặc copy sang bare-metal)"

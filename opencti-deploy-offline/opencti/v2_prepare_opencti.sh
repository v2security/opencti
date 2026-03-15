#!/bin/bash
###############################################################################
# v2_prepare_opencti.sh — Chuẩn bị source OpenCTI Platform cho offline deploy
#
# Chạy TRÊN HOST (trước khi docker compose up hoặc copy sang bare-metal).
# Copy source code + build output + node_modules + pip packages từ repo
# vào thư mục opencti/ (deploy folder) sẵn sàng mount/copy vào target.
#
# Prerequisites:
#   - Backend đã build xong (v2_build_backend.sh → build/back.js)
#   - Frontend đã build xong (v2_build_frontend.sh → builder/prod/build/)
#   - runtime/python312.tar.gz có sẵn (Python 3.12 portable)
#
# Usage:
#   cd opencti-deploy-offline/opencti
#   ./v2_prepare_opencti.sh
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR"                                           # opencti-deploy-offline/opencti/
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"                       # repo root (parent of opencti-deploy-offline)
OFFLINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"                        # opencti-deploy-offline/
GRAPHQL="$REPO_ROOT/opencti-platform/opencti-graphql"
FRONT="$REPO_ROOT/opencti-platform/opencti-front"
CLIENT="$REPO_ROOT/client-python"
YARNRC="$REPO_ROOT/opencti-platform/.yarnrc.yml"

log()   { echo -e "\e[32m[PREPARE-PLATFORM]\e[0m $1"; }
warn()  { echo -e "\e[33m[PREPARE-PLATFORM]\e[0m $1"; }
error() { echo -e "\e[31m[PREPARE-PLATFORM]\e[0m $1" >&2; exit 1; }

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
[[ -d "$GRAPHQL/build" ]]         || error "build/ not found — run v2_build_backend.sh first!"
[[ -d "$GRAPHQL/node_modules" ]]  || error "node_modules/ not found — run v2_build_backend.sh first!"
[[ -f "$GRAPHQL/package.json" ]]  || error "package.json not found at $GRAPHQL"
[[ -d "$CLIENT/pycti" ]]          || error "client-python not found at $CLIENT"
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
log "  Preparing OpenCTI Platform deployment"
log "══════════════════════════════════════════════════════════════"
log "  Repo:   $REPO_ROOT"
log "  Deploy: $DEPLOY_DIR"
log ""

# ══════════════════════════════════════════════════════════════
# COPY SOURCE + BUILD
# ══════════════════════════════════════════════════════════════
log "Syncing src/..."
rsync -a --delete "$GRAPHQL/src/" "$DEPLOY_DIR/src/"

# ── Patch: check_indicator.py (EQL subprocess isolation) ─────
PATCH_SRC="$OFFLINE_DIR/config/check_indicator.py"
PATCH_DST="$DEPLOY_DIR/src/python/runtime/check_indicator.py"
if [[ -f "$PATCH_SRC" ]]; then
    log "Patching check_indicator.py (EQL subprocess fix)..."
    cp -f "$PATCH_SRC" "$PATCH_DST"
else
    warn "config/check_indicator.py not found — skipping EQL patch"
fi

log "Syncing build/ (~40MB)..."
rsync -a --delete "$GRAPHQL/build/" "$DEPLOY_DIR/build/"

log "Syncing node_modules/ (~485MB, may take a moment)..."
rsync -a --delete "$GRAPHQL/node_modules/" "$DEPLOY_DIR/node_modules/"

log "Syncing config/..."
rsync -a --delete "$GRAPHQL/config/" "$DEPLOY_DIR/config/"

log "Syncing static/..."
rsync -a --delete "$GRAPHQL/static/" "$DEPLOY_DIR/static/"

log "Syncing script/..."
rsync -a --delete "$GRAPHQL/script/" "$DEPLOY_DIR/script/"

log "Copying package.json + .yarnrc.yml..."
cp -f "$GRAPHQL/package.json" "$DEPLOY_DIR/package.json"
[[ -f "$YARNRC" ]] && cp -f "$YARNRC" "$DEPLOY_DIR/.yarnrc.yml"

# ── Frontend → public/ ───────────────────────────────────────
if [[ -d "$FRONT/builder/prod/build" ]]; then
    log "Syncing frontend build → public/..."
    rsync -a --delete "$FRONT/builder/prod/build/" "$DEPLOY_DIR/public/"
else
    error "Frontend builder/prod/build/ not found! Chạy v2_build_frontend.sh trước!"
fi

# ── Client Python ────────────────────────────────────────────
log "Syncing client-python/..."
mkdir -p "$DEPLOY_DIR/client-python"
rsync -a --delete \
    --exclude='__pycache__' \
    --exclude='*.egg-info' \
    --exclude='.git' \
    "$CLIENT/" "$DEPLOY_DIR/client-python/"

# ══════════════════════════════════════════════════════════════
# DOWNLOAD PIP PACKAGES (offline install later)
# Dùng Python 3.12 từ runtime → pip download sẽ resolve đúng cp312
# ══════════════════════════════════════════════════════════════
log "Downloading pip packages for platform (via Python 3.12)..."
mkdir -p "$DEPLOY_DIR/.pip-packages"

if [[ -f "$GRAPHQL/src/python/requirements.txt" ]]; then
    $PIP312 download \
        -r "$GRAPHQL/src/python/requirements.txt" \
        -d "$DEPLOY_DIR/.pip-packages" \
        --quiet 2>/dev/null || warn "Some pip packages failed to download"
fi

if [[ -f "$CLIENT/requirements.txt" ]]; then
    $PIP312 download \
        -r "$CLIENT/requirements.txt" \
        -d "$DEPLOY_DIR/.pip-packages" \
        --quiet 2>/dev/null || warn "Some client-python deps failed"
fi
log "  ✓ $(ls "$DEPLOY_DIR/.pip-packages/" | wc -l) packages ready"

log ""
log "══════════════════════════════════════════════════════════════"
log "  ✓ Platform deployment READY"
log "══════════════════════════════════════════════════════════════"
log "  Deploy dir: $DEPLOY_DIR"
log ""
log "  Contents prepared:"
log "    src/, build/, node_modules/, config/, static/, script/"
log "    package.json, .yarnrc.yml, client-python/, .pip-packages/"
log ""
log "  Next: docker compose up -d  (hoặc copy sang bare-metal)"

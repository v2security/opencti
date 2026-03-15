#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# v2_build_backend.sh — Build OpenCTI backend (yarn install + build:prod)
#
# Chạy TRÊN HOST (máy build). Extracts Python 3.12 + Node.js 22
# từ runtime/, đưa vào PATH, rồi build backend.
# node-calls-python native addon compiles against Python 3.12
# automatically vì Python 3.12 FIRST in PATH.
#
# Requires:  runtime/python312.tar.gz  (from v2-build-python.sh)
#            runtime/nodejs22.tar.gz   (from v2-build-nodejs.sh)
#            gcc-c++, make on build machine
# Produces:  opencti-graphql/build/back.js + node_modules/
#
# Usage:
#   cd opencti-deploy-offline/opencti
#   ./v2_build_backend.sh
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BASE_DIR/.." && pwd)"
RUNTIME_DIR="$BASE_DIR/runtime"
GRAPHQL_DIR="$REPO_ROOT/opencti-platform/opencti-graphql"

log() { echo "  $1 $2"; }

# ── Skip if already built ────────────────────────────────────
if [[ -f "$GRAPHQL_DIR/build/back.js" ]]; then
    log "✓" "build/back.js exists → skip (delete build/ to rebuild)"
    exit 0
fi

echo "▸ Building OpenCTI backend"

# ── Pre-checks ───────────────────────────────────────────────
[[ -f "$RUNTIME_DIR/python312.tar.gz" ]] || { log "✗" "Missing: runtime/python312.tar.gz"; exit 1; }
[[ -f "$RUNTIME_DIR/nodejs22.tar.gz" ]]  || { log "✗" "Missing: runtime/nodejs22.tar.gz"; exit 1; }

# ── Extract runtimes to temp ──────────────────────────────────
TMP="/tmp/build-env"
rm -rf "$TMP" && mkdir -p "$TMP"

log "→" "Extracting Python 3.12 + Node.js 22..."
tar -xzf "$RUNTIME_DIR/python312.tar.gz" -C "$TMP/"
tar -xzf "$RUNTIME_DIR/nodejs22.tar.gz"  -C "$TMP/"

# Python 3.12 FIRST in PATH → node-calls-python compiles against 3.12
export PATH="$TMP/python312/bin:$TMP/nodejs/bin:$PATH"
export LD_LIBRARY_PATH="$TMP/python312/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

ln -sf "$TMP/python312/bin/python3.12" "$TMP/python312/bin/python3" 2>/dev/null || true
ln -sf "$TMP/python312/bin/python3.12-config" "$TMP/python312/bin/python3-config" 2>/dev/null || true

log "✓" "Python: $(python3 --version) | Node: $(node --version)"

# ── Enable corepack + node-gyp ───────────────────────────────
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
"$TMP/nodejs/bin/corepack" enable --install-directory "$TMP/nodejs/bin" 2>/dev/null || true
npm install -g node-gyp 2>&1 | tail -2

# ── Prepare workspace ────────────────────────────────────────
cp "$REPO_ROOT/opencti-platform/.yarnrc.yml" "$GRAPHQL_DIR/.yarnrc.yml" 2>/dev/null || true
rm -rf "$GRAPHQL_DIR/node_modules/node-calls-python/build" 2>/dev/null || true

# ── Build ─────────────────────────────────────────────────────
cd "$GRAPHQL_DIR"

log "→" "yarn install..."
yarn install 2>&1 | tail -5

# Rebuild node-calls-python native addon against Python 3.12
# Yarn does not re-trigger node-gyp when enableScripts: false and node_modules already linked
log "→" "Rebuilding node-calls-python native addon..."
(cd "$GRAPHQL_DIR/node_modules/node-calls-python" && node-gyp rebuild 2>&1 | tail -5)

log "→" "pip install requirements..."
python3 -m pip install --upgrade pip 2>&1 | tail -1 || true
python3 -m pip install -q -r src/python/requirements.txt 2>&1 | tail -3 || true

log "→" "yarn build:prod..."
NODE_OPTIONS="--max_old_space_size=8192" yarn build:prod 2>&1 | tail -10

[[ -f "$GRAPHQL_DIR/build/back.js" ]] || { log "✗" "build/back.js not found!"; exit 1; }

# ── Cleanup ───────────────────────────────────────────────────
rm -rf "$TMP"

log "✓" "Backend built: $(du -sh "$GRAPHQL_DIR/build" | cut -f1)"

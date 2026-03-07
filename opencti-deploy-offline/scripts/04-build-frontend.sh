#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# 04-build-frontend.sh — Build OpenCTI frontend (React + Relay)
#
# Uses Node.js 22 (from 02-build-nodejs.sh) to build the frontend.
# Relay compiler needs the GraphQL schema from opencti-graphql.
#
# Requires:  files/nodejs22.tar.gz (from 02-build-nodejs.sh)
#            opencti-graphql/config/schema/opencti.graphql
# Produces:  opencti-front/builder/prod/build/  (index.html, etc.)
# Time:      ~5-10 min
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BASE_DIR/.." && pwd)"
FILES_DIR="$BASE_DIR/files"

FRONT_DIR="$REPO_ROOT/opencti-platform/opencti-front"
GRAPHQL_SCHEMA="$REPO_ROOT/opencti-platform/opencti-graphql/config/schema/opencti.graphql"

log() { echo "  $1 $2"; }

# ── Skip if already built ────────────────────────────────────
if [[ -f "$FRONT_DIR/builder/prod/build/index.html" ]]; then
    log "✓" "builder/prod/build/index.html exists → skip (delete builder/prod/build/ to rebuild)"
    exit 0
fi

echo "▸ Building OpenCTI frontend"

# ── Extract Node.js to temp ──────────────────────────────────
TMP="/tmp/build-env-front"
rm -rf "$TMP" && mkdir -p "$TMP"

log "→" "Extracting Node.js 22..."
tar -xzf "$FILES_DIR/nodejs22.tar.gz" -C "$TMP/"

export PATH="$TMP/nodejs/bin:$PATH"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
"$TMP/nodejs/bin/corepack" enable --install-directory "$TMP/nodejs/bin" 2>/dev/null || true

log "✓" "Node: $(node --version) | npm: $(npm --version)"

# ── Verify graphql schema (needed by relay compiler) ─────────
[[ -f "$GRAPHQL_SCHEMA" ]] || { log "✗" "Missing: $GRAPHQL_SCHEMA"; exit 1; }

# ── Prepare workspace ────────────────────────────────────────
cp "$REPO_ROOT/opencti-platform/.yarnrc.yml" "$FRONT_DIR/.yarnrc.yml" 2>/dev/null || true

# ── Build ─────────────────────────────────────────────────────
cd "$FRONT_DIR"

log "→" "yarn install..."
yarn install 2>&1 | tail -5

log "→" "yarn build:standalone (relay + esbuild)..."
NODE_OPTIONS="--max_old_space_size=8192" yarn build:standalone 2>&1 | tail -10

[[ -f "$FRONT_DIR/builder/prod/build/index.html" ]] || { log "✗" "index.html not found after build!"; exit 1; }

# ── Cleanup ───────────────────────────────────────────────────
rm -rf "$TMP"

log "✓" "Frontend built: $(du -sh "$FRONT_DIR/builder/prod/build" | cut -f1)"

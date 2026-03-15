#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# 02-build-nodejs.sh — Download Node.js 22 pre-built binary
#
# Node.js 22 KHÔNG cần build từ source. Dùng trực tiếp
# pre-built binary từ nodejs.org (linux-x64).
#
# Requires:  runtime/node-v22.15.0-linux-x64.tar.xz (pre-downloaded)
#            OR internet để download
# Output:    runtime/nodejs22.tar.gz
# Target:    /opt/nodejs (on deploy server)
# Time:      ~10 giây (chỉ extract + repack)
#
# Pre-download (trên máy có internet):
#   curl -fSL https://nodejs.org/dist/v22.15.0/node-v22.15.0-linux-x64.tar.xz \
#        -o files/node-v22.15.0-linux-x64.tar.xz
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR="$(cd "$SCRIPT_DIR/../runtime" && pwd)"

NODE_VERSION="${NODE_VERSION:-22.15.0}"
NODE_TARBALL="node-v${NODE_VERSION}-linux-x64.tar.xz"
OUTPUT="nodejs22.tar.gz"

log() { echo "  $1 $2"; }

# ── Pre-checks ───────────────────────────────────────────────
if [[ -f "$RUNTIME_DIR/$OUTPUT" ]]; then
    log "✓" "$OUTPUT exists → skip (delete to rebuild)"
    exit 0
fi

mkdir -p "$RUNTIME_DIR"
echo "▸ Preparing Node.js $NODE_VERSION pre-built binary → runtime/$OUTPUT"

# ── Get pre-built binary ─────────────────────────────────────
if [[ -f "$RUNTIME_DIR/$NODE_TARBALL" ]]; then
    log "→" "Using pre-downloaded: $NODE_TARBALL"
else
    log "→" "Downloading $NODE_TARBALL..."
    command -v curl >/dev/null || { log "✗" "curl required (or pre-download $NODE_TARBALL)"; exit 1; }
    curl -fSL --progress-bar \
        "https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TARBALL}" \
        -o "$RUNTIME_DIR/$NODE_TARBALL"
    log "✓" "Downloaded $NODE_TARBALL"
fi

# ── Extract + repack as nodejs22.tar.gz ──────────────────────
STAGING="/tmp/nodejs-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"

log "→" "Extracting $NODE_TARBALL..."
tar -xJf "$RUNTIME_DIR/$NODE_TARBALL" -C "$STAGING"

# Rename node-v22.15.0-linux-x64/ → nodejs/
mv "$STAGING/node-v${NODE_VERSION}-linux-x64" "$STAGING/nodejs"

# Verify
log "→" "Verifying..."
NODE_BIN="$STAGING/nodejs/bin/node"
[[ -x "$NODE_BIN" ]] || { log "✗" "node binary not found after extract"; exit 1; }

NODE_VER=$("$NODE_BIN" -v 2>/dev/null || echo "unknown")
NPM_VER=$("$STAGING/nodejs/bin/npm" -v 2>/dev/null || echo "unknown")
log "✓" "node: $NODE_VER, npm: $NPM_VER"

# Enable corepack (for yarn)
log "→" "Enabling corepack..."
"$STAGING/nodejs/bin/corepack" enable 2>/dev/null || true

# Pack
log "→" "Creating $OUTPUT..."
cd "$STAGING"
tar -czf "$RUNTIME_DIR/$OUTPUT" nodejs/
rm -rf "$STAGING"

SIZE=$(du -h "$RUNTIME_DIR/$OUTPUT" | cut -f1)
log "✓" "Node.js $NODE_VERSION binary: $SIZE → runtime/$OUTPUT"

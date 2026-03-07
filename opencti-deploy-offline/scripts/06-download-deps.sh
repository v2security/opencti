#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# 06-download-deps.sh — Download Python packages for offline install
#
# Uses Python 3.12 (from 01-build-python.sh) to download all
# pip packages needed by platform and worker.
#
# Requires:  files/python312.tar.gz (from 01-build-python.sh)
#            Internet access
# Output:    files/python-deps.tar.gz
#
# Contents:
#   platform/   ← pip packages for opencti-graphql
#   worker/     ← pip packages for opencti-worker
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BASE_DIR/.." && pwd)"
FILES_DIR="$BASE_DIR/files"

OUTPUT="python-deps.tar.gz"
STAGING="/tmp/opencti-python-deps"

PLATFORM_REQS="$REPO_ROOT/opencti-platform/opencti-graphql/src/python/requirements.txt"
WORKER_REQS="$REPO_ROOT/opencti-worker/src/requirements.txt"
CLIENT_DIR="$REPO_ROOT/client-python"

log() { echo "  $1 $2"; }

echo "▸ Downloading Python packages → files/$OUTPUT"

# ── Extract Python 3.12 ──────────────────────────────────────
TMP="/tmp/python312-for-deps"
rm -rf "$TMP" && mkdir -p "$TMP"
tar -xzf "$FILES_DIR/python312.tar.gz" -C "$TMP"

PY="$TMP/python312/bin/python3.12"
export LD_LIBRARY_PATH="$TMP/python312/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

$PY -m pip install --upgrade pip 2>&1 | tail -1 || true
PIP="$PY -m pip"
log "✓" "Using: $($PY --version), $($PIP --version 2>&1 | head -1)"

# ── Staging ───────────────────────────────────────────────────
rm -rf "$STAGING"
mkdir -p "$STAGING/platform" "$STAGING/worker"

# ── Build pycti wheel ────────────────────────────────────────
PYCTI_WHEEL=""
if [[ -d "$CLIENT_DIR" ]]; then
    log "→" "Building pycti wheel..."
    mkdir -p "$STAGING/pycti-wheel"
    $PIP wheel --no-deps -w "$STAGING/pycti-wheel" "$CLIENT_DIR" 2>&1 | tail -3 || true
    PYCTI_WHEEL=$(ls "$STAGING/pycti-wheel"/pycti-*.whl 2>/dev/null | head -1)
    [[ -n "$PYCTI_WHEEL" ]] && log "✓" "pycti: $(basename "$PYCTI_WHEEL")"
fi

# ── Platform packages ─────────────────────────────────────────
if [[ -f "$PLATFORM_REQS" ]]; then
    log "→" "Platform packages..."
    $PIP download -d "$STAGING/platform" -r "$PLATFORM_REQS" 2>&1 | tail -5 || true
    if [[ -n "$PYCTI_WHEEL" ]]; then
        cp "$PYCTI_WHEEL" "$STAGING/platform/"
        $PIP download -d "$STAGING/platform" "$PYCTI_WHEEL" 2>&1 | tail -3 || true
    fi
    log "✓" "Platform packages downloaded"
fi

# ── Worker packages ───────────────────────────────────────────
if [[ -f "$WORKER_REQS" ]]; then
    log "→" "Worker packages..."
    $PIP download -d "$STAGING/worker" -r "$WORKER_REQS" 2>&1 | tail -5 || true
    if [[ -n "$PYCTI_WHEEL" ]]; then
        cp "$PYCTI_WHEEL" "$STAGING/worker/"
        $PIP download -d "$STAGING/worker" "$PYCTI_WHEEL" 2>&1 | tail -3 || true
    fi
    $PIP download -d "$STAGING/worker" pika pyyaml 2>&1 | tail -3 || true
    log "✓" "Worker packages downloaded"
fi

# ── Create tarball ────────────────────────────────────────────
mkdir -p "$FILES_DIR"
cd "$STAGING"
tar -czf "$FILES_DIR/$OUTPUT" .
rm -rf "$STAGING" "$TMP"

log "✓" "Python deps: $(du -h "$FILES_DIR/$OUTPUT" | cut -f1) → files/$OUTPUT"

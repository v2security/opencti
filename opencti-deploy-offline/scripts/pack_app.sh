#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# pack_app.sh — Pack all components into one offline deploy package
#
# Orchestrates 6 sub-scripts then combines everything into a
# single tarball ready for offline deployment.
#
# Requires:  Docker (for runtimes), gcc-c++, make on build machine
# Output:    files/opencti-app-package.tar.gz
#
# Sub-scripts:
#   01-build-python.sh    → files/python312.tar.gz         (compile in Docker)
#   02-build-nodejs.sh    → files/nodejs22.tar.gz          (pre-built binary)
#   03-build-backend.sh   → opencti-graphql/build/back.js  (yarn build:prod)
#   04-build-frontend.sh  → opencti-front/builder/prod/build/ (yarn build:standalone)
#   05-copy-source.sh     → files/opencti-source.tar.gz    (source + build artifacts)
#   06-download-deps.sh   → files/python-deps.tar.gz       (offline pip packages)
#
# Package layout:
#   runtimes/python312/    Python 3.12 (compiled, --enable-shared)
#   runtimes/nodejs/       Node.js 22 (pre-built binary from nodejs.org)
#   platform/              OpenCTI backend source + build artifacts
#   worker/src/            Worker Python source
#   client-python/         pycti library
#   python-packages/       Offline pip packages (platform + worker)
#
# Usage:
#   bash scripts/pack_app.sh                  # Full build
#   bash scripts/pack_app.sh --skip-runtimes  # Reuse existing runtime tarballs
#   bash scripts/pack_app.sh --skip-deps      # Skip Python package download
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FILES_DIR="$BASE_DIR/files"

OUTPUT="opencti-app-package.tar.gz"
STAGING="/tmp/opencti-app-staging"

# ── Parse flags ──────────────────────────────────────────────
SKIP_RUNTIMES=false
SKIP_DEPS=false
for arg in "$@"; do
    case "$arg" in
        --skip-runtimes) SKIP_RUNTIMES=true ;;
        --skip-deps)     SKIP_DEPS=true ;;
        --help|-h)
            echo "Usage: $0 [--skip-runtimes] [--skip-deps]"
            echo "  --skip-runtimes  Reuse existing python312.tar.gz + nodejs22.tar.gz"
            echo "  --skip-deps      Skip Python package download"
            exit 0 ;;
    esac
done

log()  { echo "  $1 $2"; }
info() { echo ""; echo "═══ [$1/7] $2 ═══"; }

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  PACK — Offline Deploy Package                  ║"
echo "║  Output: files/$OUTPUT     ║"
echo "╚══════════════════════════════════════════════════╝"

TOTAL_START=$(date +%s)

# ═════════════════════════════════════════════════════════════
# 1. Build Python 3.12 runtime (compile from source in Docker)
# ═════════════════════════════════════════════════════════════
info 1 "Python 3.12 runtime (compile from source)"
if [[ "$SKIP_RUNTIMES" == "true" ]]; then
    [[ -f "$FILES_DIR/python312.tar.gz" ]] || { log "✗" "python312.tar.gz not found"; exit 1; }
    log "⏭" "Skipped (--skip-runtimes)"
else
    bash "$SCRIPT_DIR/01-build-python.sh"
fi

# ═════════════════════════════════════════════════════════════
# 2. Download Node.js 22 pre-built binary
# ═════════════════════════════════════════════════════════════
info 2 "Node.js 22 pre-built binary"
if [[ "$SKIP_RUNTIMES" == "true" ]]; then
    [[ -f "$FILES_DIR/nodejs22.tar.gz" ]] || { log "✗" "nodejs22.tar.gz not found"; exit 1; }
    log "⏭" "Skipped (--skip-runtimes)"
else
    bash "$SCRIPT_DIR/02-build-nodejs.sh"
fi

# ═════════════════════════════════════════════════════════════
# 3. Build OpenCTI backend (yarn install + build:prod)
# ═════════════════════════════════════════════════════════════
info 3 "Build OpenCTI backend"
bash "$SCRIPT_DIR/03-build-backend.sh"

# ═════════════════════════════════════════════════════════════
# 4. Build OpenCTI frontend (React + Relay → public/)
# ═════════════════════════════════════════════════════════════
info 4 "Build OpenCTI frontend"
bash "$SCRIPT_DIR/04-build-frontend.sh"

# ═════════════════════════════════════════════════════════════
# 5. Copy OpenCTI source + build artifacts
# ═════════════════════════════════════════════════════════════
info 5 "Copy OpenCTI source"
bash "$SCRIPT_DIR/05-copy-source.sh"

# ═════════════════════════════════════════════════════════════
# 6. Download Python packages
# ═════════════════════════════════════════════════════════════
info 6 "Download Python packages"
if [[ "$SKIP_DEPS" == "true" ]]; then
    log "⏭" "Skipped (--skip-deps)"
else
    bash "$SCRIPT_DIR/06-download-deps.sh"
fi

# ═════════════════════════════════════════════════════════════
# 7. Assemble final package
# ═════════════════════════════════════════════════════════════
info 7 "Assemble package"

rm -rf "$STAGING"
mkdir -p "$STAGING/runtimes"

# Extract runtimes
log "→" "Extracting runtimes..."
tar -xzf "$FILES_DIR/python312.tar.gz" -C "$STAGING/runtimes/"
tar -xzf "$FILES_DIR/nodejs22.tar.gz"  -C "$STAGING/runtimes/"

# Extract source
log "→" "Extracting source..."
tar -xzf "$FILES_DIR/opencti-source.tar.gz" -C "$STAGING/"

# Extract Python deps
if [[ -f "$FILES_DIR/python-deps.tar.gz" ]]; then
    log "→" "Extracting Python deps..."
    mkdir -p "$STAGING/python-packages"
    tar -xzf "$FILES_DIR/python-deps.tar.gz" -C "$STAGING/python-packages/"
fi

# Create final package
log "→" "Creating $OUTPUT..."
mkdir -p "$FILES_DIR"
cd "$STAGING"
tar -czf "$FILES_DIR/$OUTPUT" .
rm -rf "$STAGING"

SIZE=$(du -h "$FILES_DIR/$OUTPUT" | cut -f1)
ELAPSED=$(( $(date +%s) - TOTAL_START ))

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  ✓ PACK APP COMPLETE                             ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  📦 $FILES_DIR/$OUTPUT"
echo "  📊 Size: $SIZE  ⏱ Time: $((ELAPSED/60))m $((ELAPSED%60))s"
echo ""
echo "  Next:"
echo "    1. Copy opencti-deploy-offline/ → target server"
echo "    2. bash scripts/setup_infra.sh  (Part 1: Infra)"
echo "    3. bash scripts/setup_app.sh    (Part 2: App)"
echo ""

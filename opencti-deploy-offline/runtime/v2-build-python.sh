#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# 01-build-python.sh — Compile Python 3.12 runtime in Docker
#
# Requires:  Docker, runtime/Python-3.12.8.tgz
# Output:    runtime/python312.tar.gz
# Target:    /opt/python312 (on deploy server)
# Time:      ~5-10 min
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR="$(cd "$SCRIPT_DIR/../runtime" && pwd)"

PYTHON_VERSION="3.12.8"
PYTHON_SRC="Python-${PYTHON_VERSION}.tgz"
OUTPUT="python312.tar.gz"
IMAGE="rockylinux:9"

log() { echo "  $1 $2"; }

# ── Pre-checks ───────────────────────────────────────────────
command -v docker >/dev/null || { log "✗" "Docker required"; exit 1; }
[[ -f "$RUNTIME_DIR/$PYTHON_SRC" ]]  || { log "✗" "Missing: runtime/$PYTHON_SRC"; exit 1; }

if [[ -f "$RUNTIME_DIR/$OUTPUT" ]]; then
    log "✓" "$OUTPUT exists → skip (delete to rebuild)"
    exit 0
fi

echo "▸ Compiling Python $PYTHON_VERSION in Docker ($IMAGE)..."

# ── Build ────────────────────────────────────────────────────
docker run --rm -v "$RUNTIME_DIR:/runtime" "$IMAGE" bash -c '
set -e
echo "  → Installing build deps..."
dnf install -y gcc make openssl-devel bzip2-devel libffi-devel \
    zlib-devel readline-devel sqlite-devel xz-devel ncurses-devel \
    tar gzip >/dev/null 2>&1

cd /tmp
tar -xzf /runtime/'"$PYTHON_SRC"'
cd Python-'"$PYTHON_VERSION"'

echo "  → Configure + compile..."
./configure --prefix=/opt/python312 --enable-shared --with-ensurepip=install \
    LDFLAGS="-Wl,-rpath,/opt/python312/lib" >/dev/null 2>&1
make -j$(nproc) >/dev/null 2>&1
make install >/dev/null 2>&1

echo "  → Verify..."
/opt/python312/bin/python3.12 -c "import ssl, sqlite3, ctypes; print(\"    Python runtime OK\")"

cd /opt && tar -czf /runtime/'"$OUTPUT"' python312/
'

SIZE=$(du -h "$RUNTIME_DIR/$OUTPUT" | cut -f1)
log "✓" "Python $PYTHON_VERSION runtime: $SIZE → runtime/$OUTPUT"

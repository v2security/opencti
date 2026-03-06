#!/usr/bin/env bash
# =============================================================================
# Build Python 3.12.8 Runtime for OpenCTI Offline Bundle
#
# Output:
#   files/python312.tar.gz
#
# Requirements:
#   - Docker
#   - files/Python-3.12.8.tgz
#
# Build Environment:
#   Rocky Linux 9 (glibc compatible)
#
# Runtime Install Path:
#   /opt/python312
#
# Usage:
#   bash build-python312-runtime.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FILES_DIR="$BASE_DIR/files"

PYTHON_VERSION="3.12.8"
PYTHON_TARBALL="Python-${PYTHON_VERSION}.tgz"
OUTPUT_ARCHIVE="python312.tar.gz"

BUILD_IMAGE="rockylinux:9"

info()   { echo ""; echo "▸ $*"; }
detail() { echo "  → $*"; }
ok()     { echo "  ✓ $*"; }
die()    { echo "  ✗ $*" >&2; exit 1; }

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  BUILD PYTHON 3.12 RUNTIME"
echo "  Version: $PYTHON_VERSION"
echo "  Output : $FILES_DIR/$OUTPUT_ARCHIVE"
echo "══════════════════════════════════════════════════════════════"

# ─────────────────────────────────────────
# Pre-checks
# ─────────────────────────────────────────

command -v docker >/dev/null || die "Docker chưa được cài"

[[ -f "$FILES_DIR/$PYTHON_TARBALL" ]] \
  || die "Thiếu $FILES_DIR/$PYTHON_TARBALL"

if [[ -f "$FILES_DIR/$OUTPUT_ARCHIVE" ]]; then
  ok "$OUTPUT_ARCHIVE đã tồn tại → skip build"
  exit 0
fi

ok "Pre-checks OK"

# ─────────────────────────────────────────
# Build Python
# ─────────────────────────────────────────

info "Compile Python $PYTHON_VERSION (Rocky 9)"

docker run --rm \
  -v "$FILES_DIR:/files" \
  "$BUILD_IMAGE" \
  bash -c '

set -e

echo "Install build dependencies..."
dnf install -y \
  gcc \
  make \
  openssl-devel \
  bzip2-devel \
  libffi-devel \
  zlib-devel \
  readline-devel \
  sqlite-devel \
  xz-devel \
  ncurses-devel \
  tar \
  gzip \
  >/dev/null 2>&1

cd /tmp

echo "Extract Python source..."
tar -xzf /files/'"$PYTHON_TARBALL"'

cd Python-'$PYTHON_VERSION'

echo "Configure build..."
./configure \
  --prefix=/opt/python312 \
  --enable-shared \
  --with-ensurepip=install \
  LDFLAGS="-Wl,-rpath,/opt/python312/lib" \
  >/dev/null 2>&1

echo "Compile..."
make -j$(nproc) >/dev/null 2>&1

echo "Install..."
make install >/dev/null 2>&1

echo "Verify runtime..."
/opt/python312/bin/python3.12 -c "import ssl, sqlite3, ctypes; print(\"Python runtime OK\")"

echo "Create archive..."
cd /opt
tar -czf /files/'"$OUTPUT_ARCHIVE"' python312/

'

ok "Build hoàn tất"

# ─────────────────────────────────────────
# Show result
# ─────────────────────────────────────────

SIZE=$(du -h "$FILES_DIR/$OUTPUT_ARCHIVE" | cut -f1)

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  Python runtime build completed"
echo "  Artifact: $FILES_DIR/$OUTPUT_ARCHIVE"
echo "  Size    : $SIZE"
echo "══════════════════════════════════════════════════════════════"
echo ""
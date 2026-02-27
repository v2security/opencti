#!/bin/bash
# =============================================================================
# ĐÓNG GÓI OPENCTI OFFLINE
# =============================================================================
#
# Yêu cầu:
#   - Docker
#   - files/Python-3.12.8.tgz (Python source)
#   - files/elasticsearch-8.17.0-linux-x86_64.tar.gz
#   - files/rabbitmq-server-generic-unix-4.1.0.tar.xz
#   - files/minio, files/mc
#   - rpm/*.rpm
#
# Output (sau khi build xong):
#   opencti-offline-deploy.tar.gz (~1.2GB)
#   └── opencti-deploy/
#       ├── files/
#       │   ├── opencti.tar.gz                 ← OpenCTI Platform (Node.js app + rebuilt native module)
#       │   ├── opencti-worker.tar.gz          ← Worker Python scripts + wheels
#       │   ├── python312.tar.gz               ← Python 3.12.8 compiled (--enable-shared)
#       │   ├── elasticsearch-8.17.0-*.tar.gz  ← Elasticsearch tarball
#       │   ├── rabbitmq-server-*.tar.xz       ← RabbitMQ tarball
#       │   ├── minio                          ← MinIO server binary
#       │   └── mc                             ← MinIO client binary
#       ├── rpm/
#       │   └── *.rpm                          ← Node.js 22, Redis, Erlang, system deps
#       ├── config/
#       │   ├── start.sh                       ← OpenCTI Platform start script
#       │   ├── elasticsearch.yml              ← ES config
#       │   ├── elasticsearch-jvm.options      ← ES JVM options
#       │   ├── elasticsearch.service          ← ES systemd service
#       │   ├── rabbitmq-server.service        ← RabbitMQ systemd service
#       │   ├── 90-opencti.conf                ← RabbitMQ config
#       │   ├── minio.service                  ← MinIO systemd service
#       │   ├── opencti.service                ← OpenCTI systemd service
#       │   └── opencti-worker@.service        ← Worker systemd service (template)
#       └── scripts/
#           ├── deploy-offline.sh              ← Deploy script
#           └── uninstall-opencti.sh           ← Uninstall script
#
# Cách dùng:
#   make package           # hoặc: bash scripts/package-for-offline.sh
#   → File: opencti-offline-deploy.tar.gz
#   → Copy lên máy đích, giải nén, chạy: bash scripts/deploy-offline.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="$(cd "$BASE_DIR/.." && pwd)"
OUTPUT_DIR="$BASE_DIR/output"
IMAGE="opencti-offline-builder"
TOTAL_STEPS=9

info()   { echo ""; echo "▸ [STEP $1/$TOTAL_STEPS] $2"; }
detail() { echo "  → $*"; }
ok()     { echo "  ✓ $*"; }
die()    { echo "  ✗ $*" >&2; exit 1; }

# Cleanup root-owned files từ Docker containers
cleanup_tmp() {
  for d in /tmp/opencti-extract /tmp/opencti-worker; do
    if [[ -d "$d" ]]; then
      docker run --rm -v "$d:/d" alpine chown -R "$(id -u):$(id -g)" /d 2>/dev/null || true
      rm -rf "$d"
    fi
  done
}
trap cleanup_tmp EXIT

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ĐÓNG GÓI OPENCTI OFFLINE"
echo "══════════════════════════════════════════════════════════════"
echo "  Workspace: $WORKSPACE_ROOT"
echo "  Output:    $OUTPUT_DIR"
echo ""

# ── Pre-checks ───────────────────────────────────────────────
echo "▸ Pre-checks"
command -v docker &>/dev/null || die "Cần Docker"
[[ -f "$WORKSPACE_ROOT/Dockerfile" ]] || die "Không tìm thấy Dockerfile ở $WORKSPACE_ROOT"
for f in "$BASE_DIR"/files/{minio,mc,elasticsearch-*.tar.gz,rabbitmq-server-generic-unix-*.tar.xz}; do
  [[ -f "$f" ]] || die "Thiếu: $f"
done
[[ $(ls "$BASE_DIR"/rpm/*.rpm 2>/dev/null | wc -l) -gt 0 ]] || die "Thiếu RPMs"
[[ -f "$BASE_DIR/files/Python-3.12.8.tgz" ]] || die "Thiếu files/Python-3.12.8.tgz"
ok "Tất cả pre-checks OK"

# ══════════════════════════════════════════════════════════════
# STEP 1: Compile Python 3.12 (nếu chưa có)
# ══════════════════════════════════════════════════════════════
info 1 "Compile Python 3.12.8 (--enable-shared, Rocky 9 glibc)"
detail "Input:  files/Python-3.12.8.tgz (source tarball)"
detail "Output: files/python312.tar.gz (compiled, ~60MB)"
if [[ -f "$BASE_DIR/files/python312.tar.gz" ]]; then
  ok "python312.tar.gz đã có → skip compile"
else
  detail "Chạy Rocky 9 container để compile..."
  docker run --rm -v "$BASE_DIR/files:/files" rockylinux:9 bash -c '
    set -e
    dnf install -y gcc make openssl-devel bzip2-devel libffi-devel \
      zlib-devel readline-devel sqlite-devel xz-devel ncurses-devel >/dev/null 2>&1
    cd /tmp && tar -xzf /files/Python-3.12.8.tgz && cd Python-3.12.8
    ./configure --prefix=/opt/python312 --enable-shared \
      LDFLAGS="-Wl,-rpath,/opt/python312/lib" >/dev/null 2>&1
    make -j$(nproc) >/dev/null 2>&1
    make install >/dev/null 2>&1
    /opt/python312/bin/python3.12 -c "import ctypes; print(\"ctypes OK\")"
    cd /opt && tar -czf /files/python312.tar.gz python312/
  '
  ok "python312.tar.gz ($(du -h "$BASE_DIR/files/python312.tar.gz" | cut -f1))"
fi

# ══════════════════════════════════════════════════════════════
# STEP 2: Docker build OpenCTI từ source
# ══════════════════════════════════════════════════════════════
info 2 "Docker build OpenCTI từ source"
detail "Dockerfile: $WORKSPACE_ROOT/Dockerfile"
detail "Image:      $IMAGE:latest"
mkdir -p "$OUTPUT_DIR/files"
cd "$WORKSPACE_ROOT"
docker build -t "$IMAGE:latest" -f Dockerfile --progress=plain .
ok "Docker build thành công"

# ══════════════════════════════════════════════════════════════
# STEP 3: Extract OpenCTI Platform từ Docker image
# ══════════════════════════════════════════════════════════════
info 3 "Extract OpenCTI Platform từ Docker image"
detail "Docker image: $IMAGE:latest"
detail "Extract to:   /tmp/opencti-extract/opencti/"
cleanup_tmp
mkdir -p /tmp/opencti-extract
CID=$(docker create "$IMAGE:latest")
docker cp "$CID:/opt/opencti" /tmp/opencti-extract/
docker rm "$CID" &>/dev/null || true
ok "Extracted OpenCTI Platform"

# ══════════════════════════════════════════════════════════════
# STEP 4: Rebuild node-calls-python (musl→glibc + Python 3.12)
# ══════════════════════════════════════════════════════════════
info 4 "Rebuild node-calls-python (glibc + Python 3.12)"
detail "Vấn đề: Docker image dùng Alpine (musl), Rocky 9 dùng glibc"
detail "Giải pháp: Rebuild native module trong Rocky 9 container"
detail "  - Mount: /tmp/opencti-extract/opencti → /opt/opencti"
detail "  - Mount: files/python312.tar.gz → /tmp/python312.tar.gz"
detail "  - Cài Node.js 22 + gcc/g++/make trong container"
detail "  - npm rebuild node-calls-python --build-from-source"
detail "  - Replace bundled .node file (musl) bằng rebuilt file (glibc)"
docker run --rm \
  -v "/tmp/opencti-extract/opencti:/opt/opencti" \
  -v "$BASE_DIR/files/python312.tar.gz:/tmp/python312.tar.gz" \
  rockylinux:9 bash -c '
    set -e
    dnf module enable -y nodejs:22 >/dev/null 2>&1
    dnf install -y nodejs npm gcc gcc-c++ make >/dev/null 2>&1
    tar -xzf /tmp/python312.tar.gz -C /opt/
    export PATH="/opt/python312/bin:$PATH"
    export LD_LIBRARY_PATH="/opt/python312/lib:${LD_LIBRARY_PATH:-}"
    cd /opt/opencti
    rm -rf node_modules/node-calls-python/build
    npm rebuild node-calls-python --build-from-source 2>&1
    REBUILT="node_modules/node-calls-python/build/Release/nodecallspython.node"
    BUNDLED=$(find build -maxdepth 1 -name "nodecallspython-*.node" -type f | head -1)
    if [[ -f "$REBUILT" ]] && [[ -n "$BUNDLED" ]]; then
      cp "$REBUILT" "$BUNDLED"
      echo "Replaced: $BUNDLED"
      echo "ldd:"
      ldd "$BUNDLED" | grep -E "python|musl|not.found" || echo "  (clean — no musl/missing refs)"
    else
      echo "ERROR: rebuilt .node not found" >&2; exit 1
    fi
  '
ok "Native module rebuilt (glibc + libpython3.12.so)"

# ══════════════════════════════════════════════════════════════
# STEP 5: Download Python wheels cho Platform
# ══════════════════════════════════════════════════════════════
info 5 "Download Python wheels cho Platform (Python 3.12)"
detail "Output: /tmp/opencti-extract/opencti/python-wheels/"
detail "Dùng cho pip install --no-index khi deploy offline"
mkdir -p /tmp/opencti-extract/opencti/python-wheels
docker run --rm -v "/tmp/opencti-extract/opencti:/opt/opencti" \
  python:3.12-slim sh -c \
  "pip download pip wheel setuptools -d /opt/opencti/python-wheels 2>/dev/null; \
   pip download -r /opt/opencti/src/python/requirements.txt -d /opt/opencti/python-wheels \
     --only-binary=:all: --platform manylinux2014_x86_64 --python-version 3.12 2>/dev/null || \
   pip download -r /opt/opencti/src/python/requirements.txt -d /opt/opencti/python-wheels 2>&1"
ok "Python wheels ($(ls /tmp/opencti-extract/opencti/python-wheels/ 2>/dev/null | wc -l) files)"

# ══════════════════════════════════════════════════════════════
# STEP 6: Đóng gói opencti.tar.gz
# ══════════════════════════════════════════════════════════════
info 6 "Đóng gói opencti.tar.gz"
detail "Source: /tmp/opencti-extract/opencti/"
detail "Output: $OUTPUT_DIR/files/opencti.tar.gz"
docker run --rm -v "/tmp/opencti-extract:/d" alpine chown -R "$(id -u):$(id -g)" /d
cd /tmp/opencti-extract
tar -czf "$OUTPUT_DIR/files/opencti.tar.gz" \
  --exclude='__pycache__' --exclude='.git' opencti/
ok "opencti.tar.gz ($(du -h "$OUTPUT_DIR/files/opencti.tar.gz" | cut -f1))"

# ══════════════════════════════════════════════════════════════
# STEP 7: Đóng gói Worker + wheels
# ══════════════════════════════════════════════════════════════
info 7 "Đóng gói OpenCTI Worker"
detail "Source: $WORKSPACE_ROOT/opencti-worker/src/*.py"
detail "Output: $OUTPUT_DIR/files/opencti-worker.tar.gz"
rm -rf /tmp/opencti-worker && mkdir -p /tmp/opencti-worker/wheels
cp "$WORKSPACE_ROOT/opencti-worker/src"/*.py /tmp/opencti-worker/
cp "$WORKSPACE_ROOT/opencti-worker/src/requirements.txt" /tmp/opencti-worker/
detail "Download worker Python wheels (3.12)"
docker run --rm -v "/tmp/opencti-worker:/w" python:3.12-slim sh -c \
  "pip download pip wheel setuptools -d /w/wheels 2>/dev/null; \
   pip download -r /w/requirements.txt -d /w/wheels \
     --only-binary=:all: --platform manylinux2014_x86_64 --python-version 3.12 2>/dev/null || \
   pip download -r /w/requirements.txt -d /w/wheels 2>&1"
docker run --rm -v "/tmp/opencti-worker:/d" alpine chown -R "$(id -u):$(id -g)" /d
cd /tmp && tar -czf "$OUTPUT_DIR/files/opencti-worker.tar.gz" \
  --exclude='__pycache__' opencti-worker/
ok "opencti-worker.tar.gz ($(du -h "$OUTPUT_DIR/files/opencti-worker.tar.gz" | cut -f1))"

# ══════════════════════════════════════════════════════════════
# STEP 8: Copy tất cả files vào output/
# ══════════════════════════════════════════════════════════════
info 8 "Copy binaries + RPMs + configs + scripts → output/"
detail "Copy infrastructure binaries:"
detail "  files/elasticsearch-*.tar.gz    → output/files/"
cp "$BASE_DIR"/files/elasticsearch-*.tar.gz "$OUTPUT_DIR/files/" 2>/dev/null || true
detail "  files/rabbitmq-server-*.tar.xz  → output/files/"
cp "$BASE_DIR"/files/rabbitmq-server-generic-unix-*.tar.xz "$OUTPUT_DIR/files/" 2>/dev/null || true
detail "  files/minio                     → output/files/"
cp "$BASE_DIR"/files/minio "$OUTPUT_DIR/files/"
detail "  files/mc                        → output/files/"
cp "$BASE_DIR"/files/mc "$OUTPUT_DIR/files/"
detail "  files/python312.tar.gz          → output/files/"
cp "$BASE_DIR"/files/python312.tar.gz "$OUTPUT_DIR/files/"
chmod +x "$OUTPUT_DIR"/files/{minio,mc}

detail "Copy RPMs:"
mkdir -p "$OUTPUT_DIR/rpm"
detail "  rpm/*.rpm ($(ls "$BASE_DIR"/rpm/*.rpm | wc -l) files) → output/rpm/"
cp "$BASE_DIR"/rpm/*.rpm "$OUTPUT_DIR/rpm/"

detail "Copy configs:"
mkdir -p "$OUTPUT_DIR/config"
detail "  config/*  → output/config/"
cp "$BASE_DIR"/config/* "$OUTPUT_DIR/config/"

detail "Copy scripts:"
mkdir -p "$OUTPUT_DIR/scripts"
detail "  scripts/deploy-offline.sh     → output/scripts/"
cp "$SCRIPT_DIR"/deploy-offline.sh "$OUTPUT_DIR/scripts/"
detail "  scripts/uninstall-opencti.sh  → output/scripts/"
cp "$SCRIPT_DIR"/uninstall-opencti.sh "$OUTPUT_DIR/scripts/" 2>/dev/null || true
detail "  scripts/gen-ssl-cert.sh       → output/scripts/"
cp "$SCRIPT_DIR"/gen-ssl-cert.sh "$OUTPUT_DIR/scripts/" 2>/dev/null || true

detail "Generate SSL certificate → output/cert/"
mkdir -p "$OUTPUT_DIR/cert"
if [[ -f "$BASE_DIR/cert/opencti.key" ]] && [[ -f "$BASE_DIR/cert/opencti.crt" ]]; then
  detail "  Dùng cert đã có từ cert/"
  cp "$BASE_DIR/cert/opencti.key" "$OUTPUT_DIR/cert/"
  cp "$BASE_DIR/cert/opencti.crt" "$OUTPUT_DIR/cert/"
else
  detail "  Gen cert mới → cert/ + output/cert/"
  bash "$SCRIPT_DIR/gen-ssl-cert.sh" "$BASE_DIR/cert"
  cp "$BASE_DIR/cert/opencti.key" "$OUTPUT_DIR/cert/"
  cp "$BASE_DIR/cert/opencti.crt" "$OUTPUT_DIR/cert/"
fi
chmod 600 "$OUTPUT_DIR/cert/opencti.key"
chmod 644 "$OUTPUT_DIR/cert/opencti.crt"
ok "SSL cert → output/cert/ (key + crt)"

ok "Tất cả files đã copy vào output/"

# ══════════════════════════════════════════════════════════════
# STEP 9: Tạo archive cuối cùng
# ══════════════════════════════════════════════════════════════
info 9 "Tạo archive cuối cùng"
ARCHIVE_DIR="/tmp/opencti-deploy"
rm -rf "$ARCHIVE_DIR" && cp -a "$OUTPUT_DIR" "$ARCHIVE_DIR"
cd /tmp && tar -czf "$BASE_DIR/opencti-offline-deploy.tar.gz" opencti-deploy/
rm -rf "$ARCHIVE_DIR"

# ══════════════════════════════════════════════════════════════
# KẾT QUẢ
# ══════════════════════════════════════════════════════════════
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  BUILD HOÀN THÀNH"
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "  📦 Archive: opencti-offline-deploy.tar.gz"
echo "     Size:    $(du -h "$BASE_DIR/opencti-offline-deploy.tar.gz" | cut -f1)"
echo ""
echo "  📁 Nội dung archive:"
echo "     files/"
echo "       opencti.tar.gz              $(du -h "$OUTPUT_DIR/files/opencti.tar.gz" 2>/dev/null | cut -f1) — Platform (Node.js + native module rebuilt)"
echo "       opencti-worker.tar.gz       $(du -h "$OUTPUT_DIR/files/opencti-worker.tar.gz" 2>/dev/null | cut -f1) — Worker (Python + wheels)"
echo "       python312.tar.gz            $(du -h "$OUTPUT_DIR/files/python312.tar.gz" 2>/dev/null | cut -f1) — Python 3.12.8 compiled"
echo "       elasticsearch-*.tar.gz      $(du -h "$OUTPUT_DIR"/files/elasticsearch-*.tar.gz 2>/dev/null | cut -f1) — Elasticsearch 8.17.0"
echo "       rabbitmq-server-*.tar.xz    $(du -h "$OUTPUT_DIR"/files/rabbitmq-server-*.tar.xz 2>/dev/null | cut -f1) — RabbitMQ 4.1.0"
echo "       minio                       $(du -h "$OUTPUT_DIR/files/minio" 2>/dev/null | cut -f1) — MinIO server"
echo "       mc                          $(du -h "$OUTPUT_DIR/files/mc" 2>/dev/null | cut -f1) — MinIO client"
echo "     rpm/                          $(ls "$OUTPUT_DIR"/rpm/*.rpm 2>/dev/null | wc -l) RPM packages"
echo "     config/                       $(ls "$OUTPUT_DIR"/config/ 2>/dev/null | wc -l) config files"
echo "     scripts/                      deploy-offline.sh, uninstall-opencti.sh"
echo ""
echo "  🚀 Deploy trên máy đích (Rocky Linux 9):"
echo "     tar -xzf opencti-offline-deploy.tar.gz"
echo "     cd opencti-deploy && bash scripts/deploy-offline.sh"
echo ""

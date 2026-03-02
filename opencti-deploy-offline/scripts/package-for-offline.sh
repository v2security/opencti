#!/bin/bash
# =============================================================================
# ĐÓNG GÓI OPENCTI OFFLINE — Build từ source code trên Rocky 9 + Node.js 22
#
# Yêu cầu: Docker, files/{Python-3.12.8.tgz, elasticsearch-*.tar.gz,
#           rabbitmq-server-*.tar.xz, minio, mc}, rpm/*.rpm
#
# Output: opencti-offline-deploy.tar.gz (~1.2GB)
# opencti-deploy/
# |-- cert
# |   |-- opencti.crt
# |   |-- opencti.key
# |-- config
# |   |-- 90-opencti.conf
# |   |-- elasticsearch-jvm.options
# |   |-- elasticsearch.service
# |   |-- elasticsearch.yml
# |   |-- minio.service
# |   |-- opencti-logrotate.conf
# |   |-- opencti-worker@.service
# |   |-- opencti.service
# |   |-- rabbitmq-server.service
# |   |-- start.sh
# |-- files
# |   |-- elasticsearch-8.17.0-linux-x86_64.tar.gz
# |   |-- mc
# |   |-- minio
# |   |-- opencti-worker.tar.gz
# |   |-- opencti.tar.gz
# |   |-- python312.tar.gz
# |   |-- rabbitmq-server-generic-unix-4.1.0.tar.xz
# |-- rpm/*
# |-- scripts
#     |-- deploy-offline.sh
#     |-- gen-ssl-cert.sh
#     |-- uninstall-opencti.sh
#
# Dùng: make package  →  copy lên máy đích  →  bash scripts/deploy-offline.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="$(cd "$BASE_DIR/.." && pwd)"
OUTPUT_DIR="$BASE_DIR/output"
ROCKY_NODE_IMAGE="rockylinux-node22"
TOTAL_STEPS=8

info()   { echo ""; echo "▸ [STEP $1/$TOTAL_STEPS] $2"; }
detail() { echo "  → $*"; }
ok()     { echo "  ✓ $*"; }
die()    { echo "  ✗ $*" >&2; exit 1; }

cleanup_tmp() {
  for d in /tmp/opencti-extract /tmp/opencti-worker /tmp/opencti-build; do
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
echo "  Workspace: $WORKSPACE_ROOT"
echo "  Output:    $OUTPUT_DIR"
echo "══════════════════════════════════════════════════════════════"

# ── Pre-checks ───────────────────────────────────────────────
echo "▸ Pre-checks"
command -v docker &>/dev/null || die "Cần Docker"
[[ -d "$WORKSPACE_ROOT/opencti-platform/opencti-front" ]] || die "Thiếu source: opencti-front/"
[[ -d "$WORKSPACE_ROOT/opencti-platform/opencti-graphql" ]] || die "Thiếu source: opencti-graphql/"
for f in "$BASE_DIR"/files/{minio,mc,elasticsearch-*.tar.gz,rabbitmq-server-generic-unix-*.tar.xz}; do
  [[ -f "$f" ]] || die "Thiếu: $f"
done
[[ $(ls "$BASE_DIR"/rpm/*.rpm 2>/dev/null | wc -l) -gt 0 ]] || die "Thiếu RPMs"
[[ -f "$BASE_DIR/files/Python-3.12.8.tgz" ]] || die "Thiếu files/Python-3.12.8.tgz"
ok "Pre-checks OK"

# ══════════════════════════════════════════════════════════════
# STEP 1: Compile Python 3.12.8 (--enable-shared, Rocky 9)
# ══════════════════════════════════════════════════════════════
info 1 "Compile Python 3.12.8 (--enable-shared, Rocky 9 glibc)"
if [[ -f "$BASE_DIR/files/python312.tar.gz" ]]; then
  ok "python312.tar.gz đã có → skip"
else
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
# STEP 2: Build base image Rocky 9 + Node.js 22
# ══════════════════════════════════════════════════════════════
# Dùng Rocky 9 (glibc) thay Alpine (musl) vì server đích là Rocky 9.
# → Native modules đã dùng glibc sẵn, không cần rebuild musl→glibc.
info 2 "Build base image Rocky 9 + Node.js 22"
# Đảm bảo output/ thuộc user hiện tại (có thể root-owned từ Docker trước đó)
if [[ -d "$OUTPUT_DIR" ]] && ! mkdir -p "$OUTPUT_DIR/files" 2>/dev/null; then
  docker run --rm -v "$OUTPUT_DIR:/d" alpine chown -R "$(id -u):$(id -g)" /d
fi
mkdir -p "$OUTPUT_DIR/files"
rm -rf /tmp/opencti-build && mkdir -p /tmp/opencti-build

docker build -t "$ROCKY_NODE_IMAGE" - <<'ROCKY_DOCKERFILE'
FROM rockylinux:9
RUN dnf module enable -y nodejs:22 && \
    dnf install -y nodejs npm gcc gcc-c++ make git python3 python3-devel \
                   openssl-devel && \
    dnf clean all && \
    npm i -g corepack node-gyp && \
    corepack enable
ROCKY_DOCKERFILE
ok "Image $ROCKY_NODE_IMAGE sẵn sàng"

# ══════════════════════════════════════════════════════════════
# STEP 3: Build Frontend từ source code
# ══════════════════════════════════════════════════════════════
info 3 "Build Frontend từ source code"
docker run --rm \
  -v "$WORKSPACE_ROOT/opencti-platform:/src:ro" \
  -v "/tmp/opencti-build:/build" \
  "$ROCKY_NODE_IMAGE" bash -c '
    set -e
    mkdir -p /build/front && cd /build/front
    cp /src/.yarnrc.yml /src/opencti-front/package.json /src/opencti-front/yarn.lock ./
    cp -a /src/opencti-front/packages ./packages
    yarn install 2>&1

    cp -a /src/opencti-front/src ./src
    cp -a /src/opencti-front/builder ./builder
    cp -a /src/opencti-front/lang ./lang 2>/dev/null || true
    cp /src/opencti-front/relay.config.json /src/opencti-front/vite.config.mts ./
    cp /src/opencti-front/tsconfig.json /src/opencti-front/tsconfig.node.json ./
    cp /src/opencti-front/index.html /src/opencti-front/index.d.ts ./ 2>/dev/null || true

    mkdir -p /build/graphql/config/schema
    cp /src/opencti-graphql/config/schema/opencti.graphql /build/graphql/config/schema/

    yarn build:standalone 2>&1
    echo "Frontend: $(du -sh builder/prod/build/ 2>/dev/null | cut -f1)"
  '
ok "Frontend build thành công"

# ══════════════════════════════════════════════════════════════
# STEP 4: Build Backend từ source code
# ══════════════════════════════════════════════════════════════
info 4 "Build Backend từ source code"
docker run --rm \
  -v "$WORKSPACE_ROOT/opencti-platform:/src:ro" \
  -v "/tmp/opencti-build:/build" \
  "$ROCKY_NODE_IMAGE" bash -c '
    set -e
    # Runtime node_modules
    mkdir -p /build/graphql-deps && cd /build/graphql-deps
    cp /src/.yarnrc.yml /src/opencti-graphql/package.json /src/opencti-graphql/yarn.lock ./
    cp -a /src/opencti-graphql/patch ./patch
    yarn install 2>&1
    yarn cache clean --all

    # Build back.js
    mkdir -p /build/graphql-builder && cd /build/graphql-builder
    cp /src/.yarnrc.yml /src/opencti-graphql/package.json /src/opencti-graphql/yarn.lock ./
    cp -a /src/opencti-graphql/patch ./patch
    yarn install 2>&1
    cp -a /src/opencti-graphql/src ./src
    cp -a /src/opencti-graphql/config ./config
    cp -a /src/opencti-graphql/static ./static
    cp -a /src/opencti-graphql/script ./script
    cp -a /src/opencti-graphql/builder ./builder
    cp /src/opencti-graphql/tsconfig.json /src/opencti-graphql/graphql-codegen.yml ./ 2>/dev/null || true
    yarn build:prod 2>&1
    echo "Backend: $(du -sh build/ 2>/dev/null | cut -f1)"
  '
ok "Backend build thành công"

# ══════════════════════════════════════════════════════════════
# STEP 5: Rebuild node-calls-python (link Python 3.12)
# ══════════════════════════════════════════════════════════════
# Nhờ Rocky 9, native module đã dùng glibc (OK). Nhưng VẪN phải rebuild vì:
#   - node-calls-python cần link dynamic với libpython
#   - Khi yarn install, nó link với Python 3.9 mặc định của Rocky 9
#   - Server đích dùng Python 3.12 custom (/opt/python312/, --enable-shared)
#   → Rebuild để .node link đúng libpython3.12.so
#   → Không rebuild = crash "libpython3.12.so: cannot open shared object file"
info 5 "Rebuild node-calls-python (link libpython3.12.so)"
docker run --rm \
  -v "/tmp/opencti-build/graphql-deps:/deps" \
  -v "$BASE_DIR/files/python312.tar.gz:/tmp/python312.tar.gz:ro" \
  "$ROCKY_NODE_IMAGE" bash -c '
    set -e
    tar -xzf /tmp/python312.tar.gz -C /opt/
    export PATH="/opt/python312/bin:$PATH"
    export LD_LIBRARY_PATH="/opt/python312/lib:${LD_LIBRARY_PATH:-}"
    python3.12 --version

    cd /deps
    rm -rf node_modules/node-calls-python/build
    npm rebuild node-calls-python --build-from-source 2>&1

    REBUILT="node_modules/node-calls-python/build/Release/nodecallspython.node"
    if [[ -f "$REBUILT" ]]; then
      echo "OK: $REBUILT"
      ldd "$REBUILT" | grep -E "python|not.found" || echo "  (clean)"
    else
      echo "ERROR: rebuilt .node not found" >&2; exit 1
    fi
  '
ok "node-calls-python rebuilt (glibc + libpython3.12.so)"

# ══════════════════════════════════════════════════════════════
# STEP 6: Assemble + Đóng gói Platform
# ══════════════════════════════════════════════════════════════
info 6 "Assemble + Đóng gói OpenCTI Platform"

rm -rf /tmp/opencti-extract
mkdir -p /tmp/opencti-extract
docker run --rm \
  -v "/tmp/opencti-build:/build:ro" \
  -v "/tmp/opencti-extract:/out" \
  -v "$WORKSPACE_ROOT/opencti-platform/opencti-graphql:/graphql-src:ro" \
  rockylinux:9 bash -c '
    set -e
    mkdir -p /out/opencti && cd /out/opencti

    cp -a /build/graphql-deps/node_modules ./node_modules
    cp -a /build/graphql-builder/build ./build
    cp -a /build/graphql-builder/static ./static
    cp -a /build/front/builder/prod/build ./public
    cp -a /graphql-src/src ./src
    cp -a /graphql-src/config ./config
    cp -a /graphql-src/script ./script 2>/dev/null || true

    # Replace bundled .node với rebuilt version (link Python 3.12)
    REBUILT="node_modules/node-calls-python/build/Release/nodecallspython.node"
    BUNDLED=$(find build -maxdepth 1 -name "nodecallspython-*.node" -type f 2>/dev/null | head -1)
    if [[ -f "$REBUILT" ]] && [[ -n "$BUNDLED" ]]; then
      cp "$REBUILT" "$BUNDLED"
      echo "Replaced: $BUNDLED"
    fi

    install -m 0777 -d logs telemetry .support
    echo "Platform: $(du -sh /out/opencti/ | cut -f1)"
  '

# Download Python wheels
detail "Download Python wheels (3.12)"
docker run --rm -v "/tmp/opencti-extract/opencti:/opt/opencti" \
  python:3.12-slim sh -c \
  "mkdir -p /opt/opencti/python-wheels && \
   pip download pip wheel setuptools -d /opt/opencti/python-wheels 2>/dev/null; \
   pip download -r /opt/opencti/src/python/requirements.txt -d /opt/opencti/python-wheels \
     --only-binary=:all: --platform manylinux2014_x86_64 --python-version 3.12 2>/dev/null || \
   pip download -r /opt/opencti/src/python/requirements.txt -d /opt/opencti/python-wheels 2>&1"

# Đóng gói
detail "Đóng gói opencti.tar.gz"
docker run --rm -v "/tmp/opencti-extract:/d" alpine chown -R "$(id -u):$(id -g)" /d
cd /tmp/opencti-extract
tar -czf "$OUTPUT_DIR/files/opencti.tar.gz" \
  --exclude='__pycache__' --exclude='.git' opencti/
ok "opencti.tar.gz ($(du -h "$OUTPUT_DIR/files/opencti.tar.gz" | cut -f1))"

# ══════════════════════════════════════════════════════════════
# STEP 7: Đóng gói Worker + wheels
# ══════════════════════════════════════════════════════════════
info 7 "Đóng gói OpenCTI Worker"
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
# STEP 8: Copy files + Tạo archive
# ══════════════════════════════════════════════════════════════
info 8 "Copy files + Tạo archive cuối cùng"

cp "$BASE_DIR"/files/elasticsearch-*.tar.gz "$OUTPUT_DIR/files/" 2>/dev/null || true
cp "$BASE_DIR"/files/rabbitmq-server-generic-unix-*.tar.xz "$OUTPUT_DIR/files/" 2>/dev/null || true
cp "$BASE_DIR"/files/minio "$BASE_DIR"/files/mc "$OUTPUT_DIR/files/"
cp "$BASE_DIR"/files/python312.tar.gz "$OUTPUT_DIR/files/"
chmod +x "$OUTPUT_DIR"/files/{minio,mc}

mkdir -p "$OUTPUT_DIR/rpm"
cp "$BASE_DIR"/rpm/*.rpm "$OUTPUT_DIR/rpm/"

mkdir -p "$OUTPUT_DIR/config"
cp "$BASE_DIR"/config/* "$OUTPUT_DIR/config/"

mkdir -p "$OUTPUT_DIR/scripts"
cp "$SCRIPT_DIR"/deploy-offline.sh "$OUTPUT_DIR/scripts/"
cp "$SCRIPT_DIR"/uninstall-opencti.sh "$OUTPUT_DIR/scripts/" 2>/dev/null || true
cp "$SCRIPT_DIR"/gen-ssl-cert.sh "$OUTPUT_DIR/scripts/" 2>/dev/null || true

mkdir -p "$OUTPUT_DIR/cert"
if [[ -f "$BASE_DIR/cert/opencti.key" ]] && [[ -f "$BASE_DIR/cert/opencti.crt" ]]; then
  cp "$BASE_DIR/cert/opencti.key" "$BASE_DIR/cert/opencti.crt" "$OUTPUT_DIR/cert/"
else
  bash "$SCRIPT_DIR/gen-ssl-cert.sh" "$BASE_DIR/cert"
  cp "$BASE_DIR/cert/opencti.key" "$BASE_DIR/cert/opencti.crt" "$OUTPUT_DIR/cert/"
fi
chmod 600 "$OUTPUT_DIR/cert/opencti.key"
chmod 644 "$OUTPUT_DIR/cert/opencti.crt"

ARCHIVE_DIR="/tmp/opencti-deploy"
rm -rf "$ARCHIVE_DIR" && cp -a "$OUTPUT_DIR" "$ARCHIVE_DIR"
cd /tmp && tar -czf "$BASE_DIR/opencti-offline-deploy.tar.gz" opencti-deploy/
rm -rf "$ARCHIVE_DIR"
ok "Tạo archive xong"

# ══════════════════════════════════════════════════════════════
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  BUILD HOÀN THÀNH"
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "  📦 $(du -h "$BASE_DIR/opencti-offline-deploy.tar.gz" | cut -f1)  opencti-offline-deploy.tar.gz"
echo ""
echo "  📁 files/"
echo "       opencti.tar.gz              $(du -h "$OUTPUT_DIR/files/opencti.tar.gz" 2>/dev/null | cut -f1)"
echo "       opencti-worker.tar.gz       $(du -h "$OUTPUT_DIR/files/opencti-worker.tar.gz" 2>/dev/null | cut -f1)"
echo "       python312.tar.gz            $(du -h "$OUTPUT_DIR/files/python312.tar.gz" 2>/dev/null | cut -f1)"
echo "     rpm/  $(ls "$OUTPUT_DIR"/rpm/*.rpm 2>/dev/null | wc -l) RPMs"
echo ""
echo "  🚀 Deploy: tar -xzf opencti-offline-deploy.tar.gz"
echo "     cd opencti-deploy && bash scripts/deploy-offline.sh"
echo ""

#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# v2_clean_build.sh — Xóa artifacts để build lại từ đầu
#
# Chạy TRÊN MÁY BUILD. Hỏi từng component muốn xóa để rebuild.
# Dùng --all để xóa tất cả không cần hỏi.
#
# Usage:
#   cd opencti-deploy-offline
#   ./v2_clean_build.sh          # Hỏi từng cái
#   ./v2_clean_build.sh --all    # Xóa tất cả
# ─────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CLEAN_ALL=false
[[ "${1:-}" == "--all" ]] && CLEAN_ALL=true

log()  { echo -e "  ${GREEN}✔${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
skip() { echo -e "  ${CYAN}⏭${NC} $1 — bỏ qua"; }

# ── Confirm helper ───────────────────────────────────────────
confirm() {
    local prompt="$1"
    if $CLEAN_ALL; then
        return 0
    fi
    echo -en "  ${YELLOW}?${NC} ${prompt} [y/N] "
    read -r ans
    [[ "$ans" =~ ^[yY]$ ]]
}

# ── Size helper ──────────────────────────────────────────────
show_size() {
    local path="$1"
    if [[ -e "$path" ]]; then
        local size
        size=$(du -sh "$path" 2>/dev/null | cut -f1)
        echo "    → $path ($size)"
    fi
}

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  v2_clean_build.sh — Xóa artifacts để build lại${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""

if $CLEAN_ALL; then
    echo -e "  ${RED}Chế độ --all: xóa TẤT CẢ artifacts${NC}"
    echo ""
fi

cleaned=0

# ─────────────────────────────────────────────────────────────
# 1. Python 3.12 runtime
# ─────────────────────────────────────────────────────────────
echo -e "${CYAN}[1/7] Python 3.12 runtime${NC}"
PY_TAR="$SCRIPT_DIR/runtime/python312.tar.gz"
if [[ -f "$PY_TAR" ]]; then
    show_size "$PY_TAR"
    if confirm "Xóa Python 3.12 runtime? (cần chạy lại v2-build-python.sh)"; then
        rm -f "$PY_TAR"
        log "Đã xóa runtime/python312.tar.gz"
        ((cleaned++))
    else
        skip "Python 3.12 runtime"
    fi
else
    warn "runtime/python312.tar.gz không tồn tại — không cần xóa"
fi
echo ""

# ─────────────────────────────────────────────────────────────
# 2. Node.js 22 runtime
# ─────────────────────────────────────────────────────────────
echo -e "${CYAN}[2/7] Node.js 22 runtime${NC}"
NODE_TAR="$SCRIPT_DIR/runtime/nodejs22.tar.gz"
if [[ -f "$NODE_TAR" ]]; then
    show_size "$NODE_TAR"
    if confirm "Xóa Node.js 22 runtime? (cần chạy lại v2-build-nodejs.sh)"; then
        rm -f "$NODE_TAR"
        log "Đã xóa runtime/nodejs22.tar.gz"
        ((cleaned++))
    else
        skip "Node.js 22 runtime"
    fi
else
    warn "runtime/nodejs22.tar.gz không tồn tại — không cần xóa"
fi
echo ""

# ─────────────────────────────────────────────────────────────
# 3. Backend build (opencti-graphql)
# ─────────────────────────────────────────────────────────────
echo -e "${CYAN}[3/7] Backend build (opencti-graphql)${NC}"
GQL_BUILD="$REPO_ROOT/opencti-platform/opencti-graphql/build"
GQL_MODULES="$REPO_ROOT/opencti-platform/opencti-graphql/node_modules"
has_backend=false
[[ -d "$GQL_BUILD" ]] && { show_size "$GQL_BUILD"; has_backend=true; }
[[ -d "$GQL_MODULES" ]] && { show_size "$GQL_MODULES"; has_backend=true; }
if $has_backend; then
    if confirm "Xóa backend build? (cần chạy lại v2_build_backend.sh)"; then
        rm -rf "$GQL_BUILD" "$GQL_MODULES"
        log "Đã xóa opencti-graphql/build/ + node_modules/"
        ((cleaned++))
    else
        skip "Backend build"
    fi
else
    warn "Backend chưa build — không cần xóa"
fi
echo ""

# ─────────────────────────────────────────────────────────────
# 4. Frontend build (opencti-front)
# ─────────────────────────────────────────────────────────────
echo -e "${CYAN}[4/7] Frontend build (opencti-front)${NC}"
FRONT_BUILD="$REPO_ROOT/opencti-platform/opencti-front/builder/prod/build"
has_frontend=false
[[ -d "$FRONT_BUILD" ]] && { show_size "$FRONT_BUILD"; has_frontend=true; }
if $has_frontend; then
    if confirm "Xóa frontend build? (cần chạy lại v2_build_frontend.sh)"; then
        rm -rf "$FRONT_BUILD"
        log "Đã xóa opencti-front/builder/prod/build/"
        ((cleaned++))
    else
        skip "Frontend build"
    fi
else
    warn "Frontend chưa build — không cần xóa"
fi
echo ""

# ─────────────────────────────────────────────────────────────
# 5. Platform prepare (opencti/ deploy folder)
# ─────────────────────────────────────────────────────────────
echo -e "${CYAN}[5/7] Platform prepare (opencti/ deploy)${NC}"
DEPLOY_CTI="$SCRIPT_DIR/opencti"
has_platform=false
for d in build node_modules src public .pip-packages; do
    [[ -d "$DEPLOY_CTI/$d" ]] && { show_size "$DEPLOY_CTI/$d"; has_platform=true; }
done
[[ -f "$DEPLOY_CTI/package.json" ]] && has_platform=true

if $has_platform; then
    if confirm "Xóa platform deploy artifacts? (cần chạy lại v2_prepare_opencti.sh)"; then
        rm -rf "$DEPLOY_CTI/build" "$DEPLOY_CTI/node_modules" "$DEPLOY_CTI/src" \
               "$DEPLOY_CTI/public" "$DEPLOY_CTI/.pip-packages" \
               "$DEPLOY_CTI/config" "$DEPLOY_CTI/static" "$DEPLOY_CTI/script" \
               "$DEPLOY_CTI/client-python" "$DEPLOY_CTI/package.json" \
               "$DEPLOY_CTI/.yarnrc.yml"
        log "Đã xóa opencti/{build,node_modules,src,public,.pip-packages,...}"
        ((cleaned++))
    else
        skip "Platform deploy"
    fi
else
    warn "Platform chưa prepare — không cần xóa"
fi
echo ""

# ─────────────────────────────────────────────────────────────
# 6. Worker prepare (opencti-worker/ deploy folder)
# ─────────────────────────────────────────────────────────────
echo -e "${CYAN}[6/7] Worker prepare (opencti-worker/ deploy)${NC}"
DEPLOY_WORKER="$SCRIPT_DIR/opencti-worker"
has_worker=false
for d in src .pip-packages; do
    [[ -d "$DEPLOY_WORKER/$d" ]] && { show_size "$DEPLOY_WORKER/$d"; has_worker=true; }
done
if $has_worker; then
    if confirm "Xóa worker deploy artifacts? (cần chạy lại v2_prepare_opencti_worker.sh)"; then
        rm -rf "$DEPLOY_WORKER/src" "$DEPLOY_WORKER/.pip-packages"
        log "Đã xóa opencti-worker/{src,.pip-packages}"
        ((cleaned++))
    else
        skip "Worker deploy"
    fi
else
    warn "Worker chưa prepare — không cần xóa"
fi
echo ""

# ─────────────────────────────────────────────────────────────
# 7. Pack archive
# ─────────────────────────────────────────────────────────────
echo -e "${CYAN}[7/7] Pack archive${NC}"
ARCHIVE="$SCRIPT_DIR/opencti-offline-deploy.tar.gz"
if [[ -f "$ARCHIVE" ]]; then
    show_size "$ARCHIVE"
    if confirm "Xóa archive? (cần chạy lại v2_pack_cti.sh)"; then
        rm -f "$ARCHIVE"
        log "Đã xóa opencti-offline-deploy.tar.gz"
        ((cleaned++))
    else
        skip "Pack archive"
    fi
else
    warn "Archive chưa tạo — không cần xóa"
fi
echo ""

# ── Summary ──────────────────────────────────────────────────
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
if [[ $cleaned -gt 0 ]]; then
    echo -e "  ${GREEN}Đã xóa $cleaned component(s).${NC} Rebuild theo thứ tự:"
    echo ""
    echo "    1. runtime/v2-build-python.sh     # Nếu xóa Python"
    echo "    2. runtime/v2-build-nodejs.sh      # Nếu xóa Node.js"
    echo "    3. opencti/v2_build_backend.sh     # Nếu xóa backend"
    echo "    4. opencti/v2_build_frontend.sh    # Nếu xóa frontend"
    echo "    5. opencti/v2_prepare_opencti.sh   # Nếu xóa platform"
    echo "    6. opencti-worker/v2_prepare_opencti_worker.sh  # Nếu xóa worker"
    echo "    7. ./v2_pack_cti.sh                # Nếu xóa archive"
else
    echo -e "  ${YELLOW}Không xóa gì cả.${NC}"
fi
echo ""

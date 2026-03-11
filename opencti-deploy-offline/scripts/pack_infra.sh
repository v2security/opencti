#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# pack_infra.sh — Pack infrastructure files into one offline package
#
# Đóng gói tất cả files cần cho setup_infra.sh thành 1 tarball duy nhất.
# SCP file này sang máy offline, extract rồi chạy setup_infra.sh là xong.
#
# Input (từ opencti-deploy-offline/):
#   files/minio                                     MinIO binary
#   files/mc                                        MinIO client (optional)
#   files/rabbitmq-server-generic-unix-*.tar.xz     RabbitMQ tarball
#   rpm/*.rpm                                       Erlang + system deps + Redis RPM
#   scripts/setup_infra.sh                          Main setup script
#   scripts/setup_app.sh                            App setup script
#   scripts/enable-services.sh                      Service enablement script
#   scripts/stop-infra.sh                           Infra cleanup script
#   scripts/stop-app.sh                             App cleanup script
#   scripts/run_minio.sh                            MinIO run script
#   scripts/run_rabbitmq.sh                         RabbitMQ run script
#   systemd/minio.service                           MinIO systemd unit
#   systemd/rabbitmq-server.service                 RabbitMQ systemd unit
#   (redis.service is provided by RPM, not packaged)
#   systemd/opencti-platform.service                Platform systemd unit
#   systemd/opencti-worker@.service                 Worker template unit
#   config/start.sh                                 Env vars (REDIS__, MINIO__, RABBITMQ__)
#   config/start-worker.sh                          Worker env vars + start
#   config/90-opencti.conf                          Sysctl tuning
#   config/opencti-logrotate.conf                   Logrotate config
#   config/elasticsearch.yml                        Elasticsearch config
#   cert/opencti.key                                SSL private key
#   cert/opencti.crt                                SSL certificate
#   config/redis.conf                               Redis config
#   config/minio.conf                               MinIO config
#   config/rabbitmq.conf                            RabbitMQ config
#   config/rabbitmq-env.conf                        RabbitMQ env config
#   config/enabled_plugins                          RabbitMQ plugins
#
# Output:  files/opencti-infra-package.tar.gz
#
# Trên máy offline:
#   tar -xzf opencti-infra-package.tar.gz -C /root/opencti-deploy
#   bash /root/opencti-deploy/scripts/setup_infra.sh
#
# Usage:
#   bash scripts/pack_infra.sh
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FILES_DIR="$BASE_DIR/files"
RPM_DIR="$BASE_DIR/rpm"

OUTPUT="opencti-infra-package.tar.gz"
STAGING="/tmp/opencti-infra-staging"

# ── Helpers ──────────────────────────────────────────────────
log()  { echo "  $1 $2"; }
info() { echo ""; echo "═══ [$1/$TOTAL] $2 ═══"; }
die()  { echo "  ✗ $*" >&2; exit 1; }

TOTAL=5
ERRORS=0

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  PACK INFRA — Offline Infrastructure Package             ║"
echo "║  Output: files/$OUTPUT                                   ║"
echo "╚══════════════════════════════════════════════════════════╝"

START_TIME=$(date +%s)

# ═════════════════════════════════════════════════════════════
# 1. Verify source files
# ═════════════════════════════════════════════════════════════
info 1 "Verify source files"

# --- files/ ---
[[ -f "$FILES_DIR/minio" ]]    || die "Missing: files/minio (MinIO binary)"
log "✓" "files/minio"

if [[ -f "$FILES_DIR/mc" ]]; then
    log "✓" "files/mc (MinIO client)"
    HAS_MC=true
else
    log "⚠" "files/mc not found (optional — MinIO client)"
    HAS_MC=false
fi

RABBITMQ_TARBALL=$(ls "$FILES_DIR"/rabbitmq-server-generic-unix-*.tar.xz 2>/dev/null | head -1) \
    || die "Missing: files/rabbitmq-server-generic-unix-*.tar.xz"
[[ -f "$RABBITMQ_TARBALL" ]] || die "Missing: files/rabbitmq-server-generic-unix-*.tar.xz"
log "✓" "files/$(basename "$RABBITMQ_TARBALL")"

# --- rpm/ ---
RPM_COUNT=$(ls "$RPM_DIR"/*.rpm 2>/dev/null | wc -l)
[[ "$RPM_COUNT" -gt 0 ]] || die "Missing: rpm/*.rpm (no RPM packages found)"
log "✓" "rpm/ ($RPM_COUNT packages)"

# Check critical RPMs
for pkg in erlang redis; do
    if ! ls "$RPM_DIR"/${pkg}-*.rpm &>/dev/null; then
        log "✗" "THIẾU: rpm/${pkg}-*.rpm"
        ERRORS=$((ERRORS + 1))
    fi
done

# Warn about RPMs that Dockerfile installs but rpm/ might miss
WARN_PKGS=""
for pkg in make tar xz curl which procps-ng iproute hostname; do
    if ! ls "$RPM_DIR"/${pkg}-*.rpm &>/dev/null 2>&1; then
        WARN_PKGS="$WARN_PKGS $pkg"
    fi
done
if [[ -n "$WARN_PKGS" ]]; then
    echo ""
    log "⚠" "Các RPM sau THIẾU trong rpm/ (cần cho máy minimal install):"
    for pkg in $WARN_PKGS; do
        log " " "  - $pkg"
    done
    log " " ""
    log " " "Nếu máy đích đã cài sẵn thì bỏ qua."
    log " " "Nếu chưa, tải bằng lệnh (trên máy có internet):"
    log " " "  dnf download --resolve --destdir=rpm/ $WARN_PKGS"
    echo ""
fi

# --- scripts/ ---
for f in setup_infra.sh setup_app.sh enable-services.sh stop-infra.sh stop-app.sh run_minio.sh run_rabbitmq.sh; do
    [[ -f "$BASE_DIR/scripts/$f" ]] || { log "✗" "Missing: scripts/$f"; ERRORS=$((ERRORS + 1)); }
    log "✓" "scripts/$f"
done

# --- systemd/ ---
for f in minio.service rabbitmq-server.service opencti-platform.service opencti-worker@.service; do
    [[ -f "$BASE_DIR/systemd/$f" ]] || { log "✗" "Missing: systemd/$f"; ERRORS=$((ERRORS + 1)); }
    log "✓" "systemd/$f"
done
log "ℹ" "redis.service — provided by RPM, not packaged"

# --- config/ ---
for f in start.sh start-worker.sh redis.conf minio.conf rabbitmq.conf rabbitmq-env.conf enabled_plugins 90-opencti.conf opencti-logrotate.conf elasticsearch.yml; do
    [[ -f "$BASE_DIR/config/$f" ]] || { log "✗" "Missing: config/$f"; ERRORS=$((ERRORS + 1)); }
    log "✓" "config/$f"
done

# --- cert/ ---
for f in opencti.key opencti.crt; do
    [[ -f "$BASE_DIR/cert/$f" ]] || { log "✗" "Missing: cert/$f"; ERRORS=$((ERRORS + 1)); }
    log "✓" "cert/$f"
done

if [[ "$ERRORS" -gt 0 ]]; then
    die "$ERRORS file(s) thiếu — không thể pack. Sửa lỗi rồi chạy lại."
fi

# ═════════════════════════════════════════════════════════════
# 2. Prepare staging directory
# ═════════════════════════════════════════════════════════════
info 2 "Prepare staging directory"

rm -rf "$STAGING"
mkdir -p "$STAGING"/{files,rpm,scripts,systemd,config,cert}
log "→" "Staging: $STAGING"

# ═════════════════════════════════════════════════════════════
# 3. Copy files to staging
# ═════════════════════════════════════════════════════════════
info 3 "Copy files to staging"

# files/
cp "$FILES_DIR/minio" "$STAGING/files/"
log "→" "files/minio"

if [[ "$HAS_MC" == "true" ]]; then
    cp "$FILES_DIR/mc" "$STAGING/files/"
    log "→" "files/mc"
fi

cp "$RABBITMQ_TARBALL" "$STAGING/files/"
log "→" "files/$(basename "$RABBITMQ_TARBALL")"

# rpm/
cp "$RPM_DIR"/*.rpm "$STAGING/rpm/"
log "→" "rpm/ ($RPM_COUNT RPMs)"

# scripts/
for f in setup_infra.sh setup_app.sh enable-services.sh stop-infra.sh stop-app.sh run_minio.sh run_rabbitmq.sh; do
    cp "$BASE_DIR/scripts/$f" "$STAGING/scripts/"
done
chmod +x "$STAGING/scripts/"*.sh
log "→" "scripts/ (7 files)"

# systemd/
for f in minio.service rabbitmq-server.service opencti-platform.service opencti-worker@.service; do
    cp "$BASE_DIR/systemd/$f" "$STAGING/systemd/"
done
log "→" "systemd/ (4 files, redis.service from RPM)"

# config/
for f in start.sh start-worker.sh redis.conf minio.conf rabbitmq.conf rabbitmq-env.conf enabled_plugins 90-opencti.conf opencti-logrotate.conf elasticsearch.yml; do
    cp "$BASE_DIR/config/$f" "$STAGING/config/"
done
log "→" "config/ (10 files)"

# cert/
for f in opencti.key opencti.crt; do
    cp "$BASE_DIR/cert/$f" "$STAGING/cert/"
done
log "→" "cert/ (opencti.key, opencti.crt)"

# ═════════════════════════════════════════════════════════════
# 4. Create tarball
# ═════════════════════════════════════════════════════════════
info 4 "Create tarball"

mkdir -p "$FILES_DIR"
cd "$STAGING"
tar -czf "$FILES_DIR/$OUTPUT" .
log "✓" "$FILES_DIR/$OUTPUT"

# ═════════════════════════════════════════════════════════════
# 5. Cleanup + summary
# ═════════════════════════════════════════════════════════════
info 5 "Summary"

rm -rf "$STAGING"

SIZE=$(du -h "$FILES_DIR/$OUTPUT" | cut -f1)
ELAPSED=$(( $(date +%s) - START_TIME ))

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✓ PACK INFRA COMPLETE                                   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  📦 Package:  files/$OUTPUT"
echo "  📊 Size:     $SIZE"
echo "  ⏱  Time:     ${ELAPSED}s"
echo ""
echo "  📋 Contents:"
echo "     files/     minio, mc, rabbitmq binaries"
echo "     rpm/       $RPM_COUNT RPM packages (Erlang + Redis + deps)"
echo "     scripts/   setup/stop infra+app, run_*.sh (7 files)"
echo "     systemd/   minio, rabbitmq, platform, worker (4 files, redis.service from RPM)"
echo "     config/    start.sh, start-worker.sh, ES, sysctl, logrotate (10 files)"
echo "     cert/      SSL certificates (opencti.key, opencti.crt)"
echo ""
echo "  🚀 Deploy trên máy offline:"
echo "     1. scp files/$OUTPUT user@offline-server:/root/"
echo "     2. ssh user@offline-server"
echo "     3. mkdir -p /root/opencti-deploy"
echo "     4. tar -xzf $OUTPUT -C /root/opencti-deploy"
echo "        (cert/ tự động được bung ra cùng package)"
echo "     5. bash /root/opencti-deploy/scripts/setup_infra.sh"
echo "     6. bash /root/opencti-deploy/scripts/setup_app.sh"
echo "     7. bash /root/opencti-deploy/scripts/enable-services.sh"
echo ""

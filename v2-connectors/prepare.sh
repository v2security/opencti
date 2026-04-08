#!/usr/bin/env bash
# ===========================================================
# prepare.sh — Tạo thư mục data cho custom connectors
# Chạy 1 lần trước khi docker compose up
#
# Usage:
#   sudo bash prepare.sh          # tạo dirs + set owner
#   sudo bash prepare.sh 1000     # chỉ định UID (vd: user deploy)
# ===========================================================
set -euo pipefail

DATA_ROOT="/opt/connector/data"
DIRS=(nvd maltrail botnet)

# UID:GID — mặc định lấy user đang sudo, hoặc truyền vào arg $1
OWNER="${1:-${SUDO_UID:-$(id -u)}}"
GROUP="${SUDO_GID:-$(id -g)}"

echo "==> Tạo thư mục data tại ${DATA_ROOT}"
mkdir -p "${DIRS[@]/#/${DATA_ROOT}/}"

echo "==> Gán quyền ${OWNER}:${GROUP}"
chown -R "${OWNER}:${GROUP}" "${DATA_ROOT}"

echo "==> Kết quả:"
ls -la "${DATA_ROOT}"
echo ""
echo "Done. Giờ có thể chạy:"
echo "  docker compose -f docker-compose-connector.yml up -d"

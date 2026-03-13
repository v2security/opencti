#!/bin/bash
#===============================================================================
# v2_stop_minio.sh - MinIO Stop Script (gọi bởi systemd ExecStop)
#===============================================================================
#
# MÔ TẢ:
#   Script dừng MinIO server gracefully. Được gọi bởi systemd khi stop service.
#   Gửi SIGTERM trước, đợi 10s, sau đó SIGKILL nếu vẫn còn chạy.
#
# INPUT:
#   Process:
#     - MinIO server đang chạy (tìm bằng pgrep -f "minio server")
#
# OUTPUT:
#   Process:
#     - MinIO server stopped
#
# USAGE:
#   # Gọi bởi systemd (ExecStop)
#   ExecStop=/usr/local/bin/v2_stop_minio.sh
#
#   # Chạy thủ công
#   bash /usr/local/bin/v2_stop_minio.sh
#
# FLOW:
#   1. Tìm MinIO processes (pgrep -f "minio server")
#   2. Gửi SIGTERM đến tất cả processes
#   3. Đợi tối đa 10 giây
#   4. Gửi SIGKILL nếu vẫn còn process
#
# LƯU Ý:
#   - Systemd cũng tự động gửi SIGTERM đến main process
#   - Script này đảm bảo cleanup và xử lý edge cases
#
#===============================================================================

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
TIMEOUT=10

#-------------------------------------------------------------------------------
# Log function
#-------------------------------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

#-------------------------------------------------------------------------------
# Stop MinIO gracefully
#-------------------------------------------------------------------------------
log "Stopping MinIO server..."

# Tìm MinIO processes
MINIO_PIDS=$(pgrep -f "minio server" 2>/dev/null || true)

if [[ -z "${MINIO_PIDS}" ]]; then
    log "No MinIO process found. Already stopped."
    exit 0
fi

log "Found MinIO processes: ${MINIO_PIDS}"

# Gửi SIGTERM (graceful shutdown)
for pid in ${MINIO_PIDS}; do
    if kill -0 "${pid}" 2>/dev/null; then
        log "Sending SIGTERM to PID ${pid}..."
        kill -TERM "${pid}" 2>/dev/null || true
    fi
done

# Đợi processes dừng
WAIT=${TIMEOUT}
while [[ ${WAIT} -gt 0 ]]; do
    MINIO_PIDS=$(pgrep -f "minio server" 2>/dev/null || true)
    if [[ -z "${MINIO_PIDS}" ]]; then
        log "MinIO stopped gracefully."
        exit 0
    fi
    log "Waiting for MinIO to stop... (${WAIT}s remaining)"
    sleep 1
    ((WAIT--))
done

# Force kill nếu vẫn còn
MINIO_PIDS=$(pgrep -f "minio server" 2>/dev/null || true)
if [[ -n "${MINIO_PIDS}" ]]; then
    log "Timeout! Force killing remaining processes..."
    for pid in ${MINIO_PIDS}; do
        kill -KILL "${pid}" 2>/dev/null || true
    done
    log "MinIO force stopped."
fi

exit 0

#!/bin/bash
###############################################################################
# v2_stop_opencti_worker.sh — Stop OpenCTI Worker
#
# Chạy TRONG container/bare-metal.
# Mount to: /usr/local/bin/v2_stop_opencti_worker.sh
# Called by: systemd (opencti-worker@.service) ExecStop
#
# Gracefully stops the worker by sending SIGTERM to python processes.
###############################################################################
set -euo pipefail

WORKER_DIR="/etc/saids/opencti-worker"

echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Stopping OpenCTI Worker..."

# Find and kill python processes running worker.py
PIDS=$(pgrep -f "python.*worker\.py" 2>/dev/null || true)

if [[ -n "$PIDS" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Sending SIGTERM to PIDs: $PIDS"
    kill -TERM $PIDS 2>/dev/null || true
    
    # Wait up to 30 seconds for graceful shutdown
    for i in {1..30}; do
        if ! pgrep -f "python.*worker\.py" &>/dev/null; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Worker stopped gracefully"
            exit 0
        fi
        sleep 1
    done
    
    # Force kill if still running
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] Force killing remaining processes..."
    pkill -9 -f "python.*worker\.py" 2>/dev/null || true
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] No worker processes found"
fi

exit 0

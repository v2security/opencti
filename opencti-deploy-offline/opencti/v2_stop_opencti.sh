#!/bin/bash
###############################################################################
# v2_stop_opencti.sh — Stop OpenCTI Platform
#
# Chạy TRONG container/bare-metal.
# Mount to: /usr/local/bin/v2_stop_opencti.sh
# Called by: systemd (opencti-platform.service) ExecStop
#
# Gracefully stops the platform by sending SIGTERM to node processes.
###############################################################################
set -euo pipefail

PLATFORM_DIR="/etc/saids/opencti"

echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Stopping OpenCTI Platform..."

# Find and kill node processes running from platform directory
PIDS=$(pgrep -f "node.*$PLATFORM_DIR" 2>/dev/null || true)

if [[ -n "$PIDS" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Sending SIGTERM to PIDs: $PIDS"
    kill -TERM $PIDS 2>/dev/null || true
    
    # Wait up to 30 seconds for graceful shutdown
    for i in {1..30}; do
        if ! pgrep -f "node.*$PLATFORM_DIR" &>/dev/null; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Platform stopped gracefully"
            exit 0
        fi
        sleep 1
    done
    
    # Force kill if still running
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] Force killing remaining processes..."
    pkill -9 -f "node.*$PLATFORM_DIR" 2>/dev/null || true
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] No platform processes found"
fi

exit 0

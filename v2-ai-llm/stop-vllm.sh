#!/usr/bin/env bash
# =============================================================================
# stop.sh - Stop the vLLM server
#
# Usage:
#   ./stop.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ">> Stopping vLLM server..."
docker compose down --remove-orphans

echo ">> vLLM server stopped."

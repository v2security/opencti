#!/usr/bin/env bash
# =============================================================================
# run-vllm.sh - Start vLLM server via docker compose
#
# Auto-detects Gemma 4 and adds tool-calling / reasoning flags.
#
# Usage:
#   ./run-vllm.sh                              # defaults from .env
#   ./run-vllm.sh -m Qwen/Qwen3-8B             # override model
#   ./run-vllm.sh -m google/gemma-4-E2B-it     # auto-adds gemma flags
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ -f .env ]]; then set -a; source .env; set +a; fi

usage() {
  cat <<'EOF'
Usage: ./run-vllm.sh [-m MODEL] [-p PORT] [-i IMAGE]

Options:
  -m, --model   HuggingFace model ID
  -p, --port    API port
  -i, --image   vLLM Docker image
  -h, --help    Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--model) export VLLM_MODEL="$2"; shift 2 ;;
    -p|--port)  export VLLM_PORT="$2";  shift 2 ;;
    -i|--image) export VLLM_IMAGE="$2"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "Error: unknown argument '$1'" >&2; usage; exit 1 ;;
  esac
done

MODEL="${VLLM_MODEL:-google/gemma-4-E2B-it}"
PORT="${VLLM_PORT:-8000}"
IMAGE="${VLLM_IMAGE:-vllm/vllm-openai:latest}"

# Auto-detect Gemma 4 → add tool-calling & reasoning flags
if [[ "$MODEL" == *gemma-4* || "$MODEL" == *gemma4* ]]; then
  export EXTRA_VLLM_ARGS="--enable-auto-tool-choice --tool-call-parser gemma4 --reasoning-parser gemma4"
  echo ">> Detected Gemma 4 model, adding tool-calling & reasoning flags"
fi

echo "==========================================="
echo "  vLLM Deployment"
echo "==========================================="
echo "  Model:     $MODEL"
echo "  Port:      $PORT"
echo "  Image:     $IMAGE"
echo "  Extra:     ${EXTRA_VLLM_ARGS:-none}"
echo "  API Key:   ****${VLLM_API_KEY:(-4)}"
echo "==========================================="

docker compose down --remove-orphans 2>/dev/null || true
docker compose up -d

echo ""
echo ">> Logs:     docker compose logs -f"
echo ">> Endpoint: http://localhost:${PORT}/v1"
echo ">> Health:   curl http://localhost:${PORT}/health"

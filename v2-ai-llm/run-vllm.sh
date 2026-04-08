#!/usr/bin/env bash
# =============================================================================
# run-vllm.sh - Start or restart vLLM with a model
#
# Usage:
#   ./run-vllm.sh                                    # Start with defaults from .env
#   ./run-vllm.sh -m <model>                         # Override model
#   ./run-vllm.sh -m <model> -p <port> -i <image>   # Override model, port, image
#
# Options:
#   -m, --model <name>   HuggingFace model ID (updates .env)
#   -p, --port  <port>   API port (updates .env)
#   -i, --image <image>  vLLM Docker image (e.g. vllm/vllm-openai:v0.8.0)
#   -h, --help           Show this help
#
# Examples:
#   ./run-vllm.sh
#   ./run-vllm.sh -m Qwen/Qwen2.5-7B-Instruct
#   ./run-vllm.sh --model meta-llama/Llama-3.1-8B-Instruct --port 8080
#   ./run-vllm.sh -m google/gemma-4-E2B-it -i vllm/vllm-openai:v0.8.0
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENV_FILE=".env"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -m, --model <name>   HuggingFace model ID (updates .env)"
    echo "  -p, --port  <port>   API port (updates .env)"
    echo "  -i, --image <image>  vLLM Docker image override"
    echo "  -h, --help           Show this help"
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
ARG_MODEL=""
ARG_PORT=""
ARG_IMAGE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--model)
            [[ $# -ge 2 ]] || { echo "Error: --model requires a value." >&2; usage; exit 1; }
            ARG_MODEL="$2"
            shift 2
            ;;
        -p|--port)
            [[ $# -ge 2 ]] || { echo "Error: --port requires a value." >&2; usage; exit 1; }
            ARG_PORT="$2"
            shift 2
            ;;
        -i|--image)
            [[ $# -ge 2 ]] || { echo "Error: --image requires a value." >&2; usage; exit 1; }
            ARG_IMAGE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown argument '$1'" >&2
            usage
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Load & update .env
# ---------------------------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE not found in $SCRIPT_DIR"
    exit 1
fi

# Helper: update a key in .env
update_env() {
    local key="$1" value="$2"
    sed "s|^${key}=.*|${key}=${value}|" "$ENV_FILE" > "${ENV_FILE}.tmp"
    mv "${ENV_FILE}.tmp" "$ENV_FILE"
}

if [[ -n "$ARG_MODEL" ]]; then
    echo ">> Updating MODEL_NAME to: $ARG_MODEL"
    update_env "MODEL_NAME" "$ARG_MODEL"
fi

if [[ -n "$ARG_PORT" ]]; then
    echo ">> Updating VLLM_PORT to: $ARG_PORT"
    update_env "VLLM_PORT" "$ARG_PORT"
fi

# Source .env for display & docker compose
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

# Image override (not persisted to .env, only for this run)
COMPOSE_ARGS=()
if [[ -n "$ARG_IMAGE" ]]; then
    export VLLM_IMAGE="$ARG_IMAGE"
fi

echo "==========================================="
echo "  vLLM Deployment"
echo "==========================================="
echo "  Model:       $MODEL_NAME"
echo "  Port:        ${VLLM_PORT:-8000}"
echo "  Image:       ${ARG_IMAGE:-vllm/vllm-openai:latest}"
echo "  GPU Util:    ${GPU_MEMORY_UTILIZATION:-0.90}"
echo "  TP Size:     ${TENSOR_PARALLEL_SIZE:-1}"
echo "  Max Length:  ${MAX_MODEL_LEN:-8192}"
echo "  Container:   ${CONTAINER_NAME:-vllm-server}"
echo "  API Key:     ${VLLM_API_KEY:+****${VLLM_API_KEY: -4}}"
echo "==========================================="

# Stop existing container if running
echo ">> Stopping existing container (if any)..."
docker compose down --remove-orphans 2>/dev/null || true

# Pull latest image
echo ">> Pulling vLLM image..."
docker compose pull

# Start the service
echo ">> Starting vLLM with model: $MODEL_NAME"
docker compose up -d

echo ""
echo ">> vLLM is starting up. It may take a few minutes to download and load the model."
echo ">> Check status:  docker compose -f $SCRIPT_DIR/docker-compose.yml logs -f"
echo ">> API endpoint:  http://localhost:${VLLM_PORT:-8000}/v1"
echo ">> Health check:  curl http://localhost:${VLLM_PORT:-8000}/health"

# vLLM Deployment

Deploy a HuggingFace model with [vLLM](https://docs.vllm.ai/) via Docker Compose.

## Prerequisites

- Docker with `nvidia-container-toolkit` installed
- NVIDIA GPU with sufficient VRAM (e.g. RTX A5000 24 GB for Gemma 4 E2B)

```bash
# Install nvidia-container-toolkit (Ubuntu/Debian)
sudo apt install -y nvidia-container-toolkit
sudo systemctl restart docker
```

## Quick Start

```bash
# 1. Edit .env — set model, image, API key, etc.
vim .env

# 2. Start (auto-adds Gemma 4 flags if model name contains "gemma-4" or "gemma4")
./run-vllm.sh

# 3. Wait for model loading (~2-5 min depending on model size)
docker compose logs -f

# 4. Stop
./stop-vllm.sh
```

## How It Works

All configuration lives in **`.env`**. The startup flow:

1. `run-vllm.sh` sources `.env` to load all variables.
2. CLI flags (`-m`, `-p`, `-i`) override the `.env` values if provided.
3. If the model name matches `*gemma-4*` or `*gemma4*`, the script **auto-exports**
   `EXTRA_VLLM_ARGS` with tool-calling & reasoning flags.
4. `docker compose up -d` reads the exported variables and starts vLLM.

**What is auto-detected:**
- `EXTRA_VLLM_ARGS` — auto-set to `--enable-auto-tool-choice --tool-call-parser gemma4 --reasoning-parser gemma4` when Gemma 4 is detected.

**What must be set manually in `.env`:**
- `VLLM_IMAGE` — the Docker image tag. Different models require different images.
- `VLLM_MODEL` — the HuggingFace model ID.
- All other config (port, GPU memory, API key, etc.)

## Switching Models

Since `VLLM_IMAGE` is **not** auto-detected, you must ensure the image is
compatible with the model. Edit `.env` or use CLI flags:

**Gemma 4** (requires `vllm/vllm-openai:gemma4` image):

```bash
# .env already configured for Gemma 4 — just run:
./run-vllm.sh

# Override model variant (image still comes from .env):
./run-vllm.sh -m google/gemma-4-12B-it

# Override image too (useful when .env points to a different model):
./run-vllm.sh -m google/gemma-4-12B-it -i vllm/vllm-openai:gemma4         # A5000 / consumer GPU
./run-vllm.sh -m google/gemma-4-12B-it -i vllm/vllm-openai:gemma4-cu130   # H100 / H200
```

**Other models** (requires `vllm/vllm-openai:latest` or compatible image):

```bash
# Option 1: Change VLLM_IMAGE in .env first, then:
./run-vllm.sh -m Qwen/Qwen3-8B

# Option 2: Override both model and image via CLI:
./run-vllm.sh -m Qwen/Qwen3-8B -i vllm/vllm-openai:latest
./run-vllm.sh -m meta-llama/Llama-3.1-8B-Instruct -i vllm/vllm-openai:latest -p 8001
```

> **Warning:** Running a non-Gemma model with the `gemma4` image, or running
> Gemma 4 with the `latest` image, will likely fail due to incompatible
> `transformers` versions.

## Gemma 4 Notes

Gemma 4 requires `transformers >= 5.5.0`, which is **not** included in the
default `vllm/vllm-openai:latest` image. Use a dedicated image tag:

| GPU | `VLLM_IMAGE` value |
|---|---|
| Consumer / A-series (CUDA 12.x) | `vllm/vllm-openai:gemma4` |
| H100 / H200 (CUDA 13.x) | `vllm/vllm-openai:gemma4-cu130` |

> **Note:** KV offloading flags (`--kv-offloading-backend`, `--disable-hybrid-kv-cache-manager`,
> `--kv-offloading-size`) are **not** compatible with Gemma 4's heterogeneous attention
> architecture in the current vLLM version — do not add them.

## Configuration (`.env`)

| Variable | Default | Description |
|---|---|---|
| `VLLM_MODEL` | `google/gemma-4-E2B-it` | HuggingFace model ID |
| `VLLM_IMAGE` | `vllm/vllm-openai:gemma4` | Docker image (**must match model**, see above) |
| `VLLM_API_KEY` | `sk-vllm-...` | API authentication key |
| `VLLM_PORT` | `8000` | API port |
| `VLLM_MAX_MODEL_LEN` | `8192` | Max context length |
| `VLLM_GPU_MEMORY_UTILIZATION` | `0.90` | GPU memory fraction (0.0–1.0) |
| `VLLM_TENSOR_PARALLEL_SIZE` | `1` | Number of GPUs for tensor parallelism |
| `CONTAINER_NAME` | `vllm-server` | Docker container name |
| `DOCKER_NETWORK` | `sophon-net` | Docker bridge network name |
| `HF_TOKEN` | _(empty)_ | HuggingFace token (required for gated models) |
| `HF_CACHE_DIR` | `~/.cache/huggingface` | Local model cache directory |
| `VLLM_ENABLE_CUDA_COMPATIBILITY` | `0` | CUDA forward compatibility (0 or 1) |
| `EXTRA_VLLM_ARGS` | _(empty)_ | Auto-set by `run-vllm.sh` for Gemma 4, or set manually |

## API Usage

OpenAI-compatible endpoint at `http://localhost:8000/v1`.

```bash
# Health check
curl http://localhost:8000/health

# Chat completion
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -d '{
    "model": "google/gemma-4-E2B-it",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## Useful Commands

```bash
docker compose logs -f          # Follow vLLM logs
make watch-gpu                  # Live nvidia-smi monitoring
make prune                      # Remove unused Docker images
docker exec vllm-server nvidia-smi   # GPU usage inside container
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `model type "gemma4" not recognized` | `transformers` too old in image | Use `vllm/vllm-openai:gemma4` image tag |
| `KeyError: '...self_attn.attn'` | KV offloading incompatible with Gemma 4 | Remove `--kv-offloading-*` flags |
| `Connection reset by peer` on curl | Model still loading | Wait for healthcheck → `healthy` |
| Container exits with OOM | Insufficient VRAM | Lower `VLLM_GPU_MEMORY_UTILIZATION` or `VLLM_MAX_MODEL_LEN` |
| `Engine core initialization failed` | Check logs for root cause above the error | `docker logs vllm-server 2>&1 \| grep -B 10 "Engine core"` |

# vLLM AI LLM Deployment

Deploy any HuggingFace LLM model using [vLLM](https://docs.vllm.ai/) with a single command.

## Prerequisites

- Docker with NVIDIA GPU support (`nvidia-container-toolkit`)
- NVIDIA GPU(s) with sufficient VRAM for your chosen model

## Quick Start

```bash
cd v2-ai-llm

# 1. Edit .env to set your model and configuration
vim .env

# 2. Start the server
chmod +x start.sh stop.sh
./start.sh
```

## Usage

### Start with model from `.env`

```bash
./start.sh
```

### Switch to a different model (updates `.env` automatically)

```bash
./start.sh Qwen/Qwen2.5-7B-Instruct
./start.sh meta-llama/Llama-3.1-8B-Instruct
./start.sh mistralai/Mistral-7B-Instruct-v0.3
```

### Stop the server

```bash
./stop.sh
```

### Check logs

```bash
docker compose logs -f
```

## Configuration (`.env`)

| Variable | Default | Description |
|---|---|---|
| `MODEL_NAME` | `google/gemma-4-E2B-it` | HuggingFace model ID |
| `VLLM_PORT` | `8000` | API port |
| `MAX_MODEL_LEN` | `8192` | Max context length |
| `GPU_MEMORY_UTILIZATION` | `0.90` | GPU memory fraction |
| `TENSOR_PARALLEL_SIZE` | `1` | Number of GPUs |
| `QUANTIZATION` | _(empty)_ | `awq`, `gptq`, `fp8`, etc. |
| `DTYPE` | `auto` | Data type |
| `HF_TOKEN` | _(empty)_ | Required for gated models |
| `MODEL_CACHE_DIR` | `./model-cache` | Local cache directory |

## API Usage

The server exposes an **OpenAI-compatible API** at `http://localhost:8000/v1`.

```bash
# List models
curl http://localhost:8000/v1/models

# Chat completion
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "google/gemma-4-E2B-it",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 512
  }'

# Health check
curl http://localhost:8000/health
```

## Multi-GPU

Set `TENSOR_PARALLEL_SIZE` in `.env` to the number of GPUs:

```env
TENSOR_PARALLEL_SIZE=2
```

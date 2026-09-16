# 🤖 Local Small LLM Docker

[![Docker Publish](https://github.com/infocyph/docker-llm-sm/actions/workflows/docker.publish.yml/badge.svg)](https://github.com/infocyph/docker-llm-sm/actions/workflows/docker.publish.yml)
![Docker Pulls](https://img.shields.io/docker/pulls/infocyph/llm-sm)
![Docker Image Size](https://img.shields.io/docker/image-size/infocyph/llm-sm)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Runtime: Ollama](https://img.shields.io/badge/Runtime-Ollama-black.svg)](https://ollama.com)

A self-contained local LLM image powered by Ollama.

The default image bakes `qwen2.5:3b` into the container during build, so it can start serving immediately without downloading model weights on first run.

## Registries

| Registry | Image |
|---|---|
| Docker Hub | `docker.io/infocyph/llm-sm` |
| GitHub Container Registry | `ghcr.io/infocyph/llm-sm` |

## Defaults

| Setting | Default |
|---|---|
| Model | `qwen2.5:3b` |
| API port | `11434` |
| Parallel requests | `1` |
| Loaded models | `1` |
| Keep alive | `5m` |
| Ollama cloud features | disabled |

`OLLAMA_NUM_PARALLEL=1` is intentionally conservative for local machines. Higher parallelism increases memory use and should be enabled only when the host has enough RAM/VRAM.

## Build

```bash
docker build -t infocyph/llm-sm:local .
```

Build with another Ollama model:

```bash
docker build \
  --build-arg OLLAMA_MODEL=qwen2.5:1.5b \
  -t infocyph/llm-sm:local .
```

The selected model is downloaded at build time and becomes part of the image.

## Run

CPU:

```bash
docker run --rm \
  --name llm-sm \
  -p 127.0.0.1:11434:11434 \
  infocyph/llm-sm:local
```

NVIDIA GPU:

```bash
docker run --rm \
  --name llm-sm \
  --gpus all \
  -p 127.0.0.1:11434:11434 \
  infocyph/llm-sm:local
```

The API is intentionally bound to localhost in these examples. Expose it to another interface only when you explicitly need network access and have appropriate network controls in place.

## Docker Compose

```bash
cp .env.example .env
docker compose up --build -d
```

Check status:

```bash
docker compose ps
```

Follow logs:

```bash
docker compose logs -f llm-sm
```

Stop:

```bash
docker compose down
```

## Native Ollama API

List models:

```bash
curl http://127.0.0.1:11434/api/tags
```

Chat:

```bash
curl http://127.0.0.1:11434/api/chat \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "qwen2.5:3b",
    "messages": [
      {"role": "user", "content": "Explain dependency injection in one paragraph."}
    ],
    "stream": false
  }'
```

## OpenAI-compatible API

Ollama supports an OpenAI-compatible API subset, including `/v1/chat/completions`.

```bash
curl http://127.0.0.1:11434/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "qwen2.5:3b",
    "messages": [
      {"role": "user", "content": "Write a short PHP example using readonly classes."}
    ]
  }'
```

For OpenAI SDK-compatible clients, use:

```text
Base URL: http://127.0.0.1:11434/v1
API key: ollama
```

The API key value is required by some clients but is not used by a default local Ollama server for authentication.

## Runtime tuning

Override runtime settings without rebuilding:

```bash
docker run --rm \
  --name llm-sm \
  -p 127.0.0.1:11434:11434 \
  -e OLLAMA_NUM_PARALLEL=2 \
  -e OLLAMA_KEEP_ALIVE=15m \
  infocyph/llm-sm:local
```

Common variables:

| Variable | Purpose |
|---|---|
| `OLLAMA_NUM_PARALLEL` | Parallel requests per model |
| `OLLAMA_MAX_LOADED_MODELS` | Maximum simultaneously loaded models |
| `OLLAMA_KEEP_ALIVE` | How long a model remains loaded |
| `OLLAMA_CONTEXT_LENGTH` | Default context length |
| `OLLAMA_MAX_QUEUE` | Maximum queued requests while busy |
| `OLLAMA_NO_CLOUD` | Disable Ollama cloud functionality |

## Model strategy

This repository intentionally bakes one small model into each built image instead of downloading the model at container startup.

Advantages:

- deterministic deployments
- immediate startup after image pull
- no first-run model download
- works offline after the image has been built/pulled
- image and model can be versioned together

The trade-off is a larger Docker image. For frequently changing or multiple models, use a standard Ollama container with a persistent model volume instead.

## Publishing

The GitHub Actions workflow follows the same release-driven pattern used by `infocyph/docker-tools`:

- publish on GitHub Release
- weekly rebuild against the current upstream Ollama image
- push to Docker Hub and GHCR
- publish `latest` and the release tag
- generate build provenance attestations

Required repository secrets:

```text
DOCKER_USERNAME
DOCKER_PASSWORD
```

GHCR authentication uses the repository `GITHUB_TOKEN`.

## License

MIT

# 🤖 Local Small LLM Docker

[![Docker Publish](https://github.com/infocyph/docker-llm-sm/actions/workflows/docker.publish.yml/badge.svg)](https://github.com/infocyph/docker-llm-sm/actions/workflows/docker.publish.yml)
[![CLI Check](https://github.com/infocyph/docker-llm-sm/actions/workflows/cli.check.yml/badge.svg)](https://github.com/infocyph/docker-llm-sm/actions/workflows/cli.check.yml)
![Docker Pulls](https://img.shields.io/docker/pulls/infocyph/llm-sm)
![Docker Image Size](https://img.shields.io/docker/image-size/infocyph/llm-sm)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Runtime: Ollama](https://img.shields.io/badge/Runtime-Ollama-black.svg)](https://ollama.com)

A self-contained small local LLM runtime powered by Ollama.

The published image bakes `qwen2.5:3b` into the image so containers can serve immediately without downloading model weights on first startup.

## Published images

Consumers use published images only. Local image builds are not part of the supported usage flow.

Both Docker Hub and GHCR use a single image repository:

| Registry | Repository |
|---|---|
| Docker Hub | `docker.io/infocyph/llm-sm` |
| GitHub Container Registry | `ghcr.io/infocyph/llm-sm` |

Two runtime variants are published through tags:

| Runtime | Moving tag | Release tag example |
|---|---|---|
| CPU / NVIDIA | `latest` | `v1.0.0` |
| AMD ROCm | `amd-latest` | `amd-v1.0.0` |

For reproducible deployments, pin a release tag instead of a moving `latest` tag.

## Defaults

| Setting | Default |
|---|---|
| Model | `qwen2.5:3b` |
| API port | `11434` |
| Parallel requests | `1` |
| Loaded models | `1` |
| Keep alive | `5m` |
| Ollama cloud features | disabled |

`OLLAMA_NUM_PARALLEL=1` is intentionally conservative for local machines. Increase it only when the host has sufficient RAM/VRAM.

## Pull

Docker Hub:

```bash
docker pull infocyph/llm-sm:latest
docker pull infocyph/llm-sm:amd-latest
```

GHCR:

```bash
docker pull ghcr.io/infocyph/llm-sm:latest
docker pull ghcr.io/infocyph/llm-sm:amd-latest
```

Pin a release when reproducibility matters:

```bash
docker pull infocyph/llm-sm:v1.0.0
docker pull infocyph/llm-sm:amd-v1.0.0
```

## Run

### CPU

```bash
docker run -d \
  --name llm-sm \
  --restart unless-stopped \
  -p 127.0.0.1:11434:11434 \
  infocyph/llm-sm:latest
```

### NVIDIA GPU

Install and configure the NVIDIA Container Toolkit on the host, then expose the GPUs with Docker's `--gpus` flag:

```bash
docker run -d \
  --name llm-sm \
  --restart unless-stopped \
  --gpus=all \
  -p 127.0.0.1:11434:11434 \
  infocyph/llm-sm:latest
```

The Docker option is `--gpus=all` / `--gpus all`.

### AMD GPU

AMD uses the ROCm-tagged image and Linux device passthrough:

```bash
docker run -d \
  --name llm-sm \
  --restart unless-stopped \
  --device=/dev/kfd \
  --device=/dev/dri \
  -p 127.0.0.1:11434:11434 \
  infocyph/llm-sm:amd-latest
```

AMD GPU support targets Linux hosts supported by Ollama/ROCm. If device permissions prevent GPU discovery, inspect the host permissions/group IDs for `/dev/kfd` and `/dev/dri` and add the required groups to the container.

To use GHCR instead, replace `infocyph/llm-sm:<tag>` with `ghcr.io/infocyph/llm-sm:<tag>`.

The API is bound to localhost in these examples. Expose it to other interfaces only when explicitly required and protected appropriately.

## Docker Compose

Copy the environment template if runtime overrides are needed:

```bash
cp .env.example .env
```

The default `compose.yml` uses the published CPU/NVIDIA image:

```yaml
services:
  llm-sm:
    image: ${LLM_SM_IMAGE:-infocyph/llm-sm:latest}
    container_name: llm-sm
    restart: unless-stopped
    ports:
      - "127.0.0.1:${OLLAMA_PORT:-11434}:11434"
    environment:
      OLLAMA_NUM_PARALLEL: ${OLLAMA_NUM_PARALLEL:-1}
      OLLAMA_MAX_LOADED_MODELS: ${OLLAMA_MAX_LOADED_MODELS:-1}
      OLLAMA_KEEP_ALIVE: ${OLLAMA_KEEP_ALIVE:-5m}
      OLLAMA_NO_CLOUD: ${OLLAMA_NO_CLOUD:-1}
```

Run it with:

```bash
docker compose pull
docker compose up -d
```

Ready-to-run examples are available under `examples/compose/`:

```text
examples/compose/
├── cpu.yml
├── nvidia.yml
└── amd.yml
```

### CPU Compose

```yaml
services:
  llm-sm:
    image: ${LLM_SM_IMAGE:-infocyph/llm-sm:latest}
    container_name: llm-sm
    restart: unless-stopped
    ports:
      - "127.0.0.1:${OLLAMA_PORT:-11434}:11434"
    environment:
      OLLAMA_NUM_PARALLEL: ${OLLAMA_NUM_PARALLEL:-1}
      OLLAMA_MAX_LOADED_MODELS: ${OLLAMA_MAX_LOADED_MODELS:-1}
      OLLAMA_KEEP_ALIVE: ${OLLAMA_KEEP_ALIVE:-5m}
      OLLAMA_NO_CLOUD: ${OLLAMA_NO_CLOUD:-1}
```

```bash
docker compose -f examples/compose/cpu.yml pull
docker compose -f examples/compose/cpu.yml up -d
```

### NVIDIA GPU Compose

```yaml
services:
  llm-sm:
    image: ${LLM_SM_IMAGE:-infocyph/llm-sm:latest}
    container_name: llm-sm
    restart: unless-stopped
    gpus: all
    ports:
      - "127.0.0.1:${OLLAMA_PORT:-11434}:11434"
    environment:
      OLLAMA_NUM_PARALLEL: ${OLLAMA_NUM_PARALLEL:-1}
      OLLAMA_MAX_LOADED_MODELS: ${OLLAMA_MAX_LOADED_MODELS:-1}
      OLLAMA_KEEP_ALIVE: ${OLLAMA_KEEP_ALIVE:-5m}
      OLLAMA_NO_CLOUD: ${OLLAMA_NO_CLOUD:-1}
```

```bash
docker compose -f examples/compose/nvidia.yml pull
docker compose -f examples/compose/nvidia.yml up -d
```

For older Compose releases, use an NVIDIA GPU device reservation instead of `gpus: all`.

### AMD GPU Compose

```yaml
services:
  llm-sm:
    image: ${LLM_SM_AMD_IMAGE:-infocyph/llm-sm:amd-latest}
    container_name: llm-sm
    restart: unless-stopped
    devices:
      - /dev/kfd:/dev/kfd
      - /dev/dri:/dev/dri
    ports:
      - "127.0.0.1:${OLLAMA_PORT:-11434}:11434"
    environment:
      OLLAMA_NUM_PARALLEL: ${OLLAMA_NUM_PARALLEL:-1}
      OLLAMA_MAX_LOADED_MODELS: ${OLLAMA_MAX_LOADED_MODELS:-1}
      OLLAMA_KEEP_ALIVE: ${OLLAMA_KEEP_ALIVE:-5m}
      OLLAMA_NO_CLOUD: ${OLLAMA_NO_CLOUD:-1}
```

```bash
docker compose -f examples/compose/amd.yml pull
docker compose -f examples/compose/amd.yml up -d
```

If AMD device permissions require explicit groups, determine the host group IDs first:

```bash
ls -lnd /dev/kfd /dev/dri /dev/dri/*
```

Then add the actual numeric IDs to `group_add`; do not copy IDs from another host.

### GHCR and pinned versions

Compose image sources can be overridden without editing the YAML:

```bash
LLM_SM_IMAGE=ghcr.io/infocyph/llm-sm:v1.0.0 \
  docker compose -f examples/compose/nvidia.yml up -d

LLM_SM_AMD_IMAGE=ghcr.io/infocyph/llm-sm:amd-v1.0.0 \
  docker compose -f examples/compose/amd.yml up -d
```

## Host CLI

The repository includes a modular Bash CLI for controlling a running `llm-sm` container and using its Ollama API.

Use it directly from the repository:

```bash
./scripts/llm-sm status
./scripts/llm-sm ask "Explain dependency injection briefly"
./scripts/llm-sm code "Write a PHP readonly DTO"
```

Install it so it can be called from any directory:

```bash
./scripts/llm-sm install
```

Default installation layout:

```text
/usr/local/bin/llm-sm
/usr/local/lib/llm-sm/lib/
/usr/local/lib/llm-sm/commands/
/usr/local/lib/llm-sm/prompts/
```

User-local installation:

```bash
./scripts/llm-sm install "$HOME/.local/bin"
```

Remove it with:

```bash
llm-sm uninstall
```

### Modular command layout

```text
scripts/
├── llm-sm
├── lib/
│   ├── core.sh
│   ├── docker.sh
│   ├── ollama.sh
│   └── commit.sh
├── prompts/
│   └── ai-commit.txt
└── commands/
    ├── ask.sh
    ├── chat.sh
    ├── prompt.sh
    ├── code.sh
    ├── review.sh
    ├── json.sh
    ├── ai-commit.sh
    └── ...
```

The entrypoint is only a dispatcher; each command lives in its own Bash module.

### Developer commands

One-shot request:

```bash
llm-sm ask "Explain PHP fibers briefly"
llm-sm ask -m qwen2.5:3b "Explain event sourcing"
```

Interactive chat:

```bash
llm-sm chat
llm-sm chat qwen2.5:3b
```

Generic prompt with system instruction and file context:

```bash
llm-sm prompt \
  --system "Answer concisely and call out assumptions" \
  --file composer.json \
  "Explain this package architecture"
```

Generate or improve code:

```bash
llm-sm code "Write a lightweight PHP rate limiter"
llm-sm code --file src/HotPath.php "Optimize this hot path without changing behavior"
cat src/HotPath.php | llm-sm code "Optimize this implementation"
```

Review code:

```bash
llm-sm review src/Service.php
llm-sm review src/Service.php "Focus on concurrency and resource leaks"
cat src/Service.php | llm-sm review
```

`review` prioritizes correctness, security, performance, concurrency, resource handling, edge cases, compatibility risks, and production failure modes.

### AI commit

Generate a commit message from staged changes using the bundled Conventional Commit + Gitmoji prompt and local Ollama inference:

```bash
git add .
llm-sm ai-commit
```

Available modes:

```bash
llm-sm ai-commit --print
llm-sm ai-commit --yes
llm-sm ai-commit --edit
llm-sm ai-commit -m qwen2.5:3b
```

The prompt is bundled at `scripts/prompts/ai-commit.txt`. This feature does not depend on Toolset, `gitx`, Gemini, or a remote prompt source.

A custom local prompt can be supplied with:

```bash
LLM_SM_AI_COMMIT_PROMPT_FILE=/path/to/prompt.txt llm-sm ai-commit
```

### Structured JSON

Use Ollama's native JSON mode:

```bash
llm-sm json "Return an object with name and version"
```

Print only the model-produced JSON value with `--response-only` / `-r`:

```bash
llm-sm json -r "Return an object with name and version"
```

A JSON Schema can be supplied directly:

```bash
llm-sm json \
  --schema schema.json \
  --response-only \
  "Describe this service"
```

### CLI commands

| Command | Purpose |
|---|---|
| `llm-sm ask [-m model] <prompt>` | One-shot request |
| `llm-sm chat [model]` | Interactive model session |
| `llm-sm prompt [options] <prompt>` | Generic prompt with system/file/stdin context |
| `llm-sm code [options] <task>` | Generate or improve code |
| `llm-sm review [options] [file...] [focus]` | Review files or piped code |
| `llm-sm json [options] <prompt>` | Native structured JSON output |
| `llm-sm ai-commit [options]` | Generate/commit a message from staged changes |
| `llm-sm status` | Container state, health, API endpoint and model |
| `llm-sm start` | Start the existing container |
| `llm-sm stop` | Stop the container |
| `llm-sm restart` | Restart the container |
| `llm-sm logs` | Follow container logs |
| `llm-sm models` | List installed Ollama models |
| `llm-sm ps` | List currently loaded models |
| `llm-sm run <model> [prompt]` | Run an explicit model |
| `llm-sm show [model]` | Show model information |
| `llm-sm pull <model>` | Pull another model into the current container |
| `llm-sm rm <model>` | Remove a model from the current container |
| `llm-sm unload [model]` | Unload a model from RAM/VRAM |
| `llm-sm ollama <args...>` | Raw Ollama CLI passthrough |
| `llm-sm api <path> [curl args...]` | Raw HTTP API access |
| `llm-sm version` | CLI and Ollama versions |
| `llm-sm install [bin-directory]` | Install executable and modules |
| `llm-sm uninstall [bin-directory]` | Remove executable and modules |

Prompts can be piped through stdin:

```bash
echo "Summarize this sentence" | llm-sm ask
```

Raw Ollama passthrough remains available:

```bash
llm-sm ollama list
llm-sm ollama show qwen2.5:3b
```

Raw API access:

```bash
llm-sm api /api/tags
```

Runtime overrides:

```bash
LLM_SM_CONTAINER=my-llm llm-sm status
LLM_SM_URL=http://127.0.0.1:12434 llm-sm api /api/tags
LLM_SM_MODEL=qwen2.5:1.5b llm-sm ask "Hello"
LLM_SM_SYSTEM="Be concise" llm-sm prompt "Explain CQRS"
```

`llm-sm pull` adds a model to the writable layer of the current container. It survives container stop/start but is lost when the container is removed or recreated. The baked model remains the reproducible deployment model.

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

Ollama exposes an OpenAI-compatible API subset, including `/v1/chat/completions`:

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

For OpenAI SDK-compatible clients:

```text
Base URL: http://127.0.0.1:11434/v1
API key: ollama
```

Some clients require a non-empty API key value even though the default local Ollama server does not use it for authentication.

## Runtime tuning

Common runtime variables:

| Variable | Purpose |
|---|---|
| `OLLAMA_NUM_PARALLEL` | Parallel requests per model |
| `OLLAMA_MAX_LOADED_MODELS` | Maximum simultaneously loaded models |
| `OLLAMA_KEEP_ALIVE` | How long a model remains loaded |
| `OLLAMA_CONTEXT_LENGTH` | Default context length |
| `OLLAMA_MAX_QUEUE` | Maximum queued requests while busy |
| `OLLAMA_NO_CLOUD` | Disable Ollama cloud functionality |

Example:

```bash
docker run -d \
  --name llm-sm \
  --restart unless-stopped \
  -p 127.0.0.1:11434:11434 \
  -e OLLAMA_NUM_PARALLEL=2 \
  -e OLLAMA_KEEP_ALIVE=15m \
  infocyph/llm-sm:latest
```

## Model strategy

One small model is baked into each published image instead of being downloaded at container startup.

Advantages:

- deterministic release images
- immediate startup after image pull
- no first-run model download
- offline operation after the image is pulled
- image and baked model can be versioned together

The trade-off is a larger image. Additional runtime model pulls are intentionally treated as ephemeral container state.

## Publishing

Publishing is maintainer-managed by GitHub Actions. Consumers do not need the Dockerfile or a local build toolchain.

Each GitHub Release publishes into both Docker Hub and GHCR:

- CPU/NVIDIA: `<release>` and `latest`
- AMD ROCm: `amd-<release>` and `amd-latest`
- immutable release tags are never changed by scheduled builds
- weekly scheduled builds refresh only `latest` and `amd-latest`
- both variants use separate Buildx cache scopes
- pushed digests receive provenance attestations

Required repository secrets for maintainers:

```text
DOCKER_USERNAME
DOCKER_PASSWORD
```

GHCR publishing uses the repository `GITHUB_TOKEN`.

## Validation

The `CLI Check` workflow validates:

- Bash syntax across the entrypoint, libraries, and command modules
- ShellCheck
- default/CPU/NVIDIA/AMD Compose definitions
- repository-layout CLI smoke tests
- installed-layout smoke tests
- bundled `ai-commit` prompt availability
- idempotent reinstall
- uninstall cleanup

## License

MIT

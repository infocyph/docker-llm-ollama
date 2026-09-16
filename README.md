# 🤖 Local Small LLM Docker

[![Docker Publish](https://github.com/infocyph/docker-llm-sm/actions/workflows/docker.publish.yml/badge.svg)](https://github.com/infocyph/docker-llm-sm/actions/workflows/docker.publish.yml)
[![CLI Check](https://github.com/infocyph/docker-llm-sm/actions/workflows/cli.check.yml/badge.svg)](https://github.com/infocyph/docker-llm-sm/actions/workflows/cli.check.yml)
![Docker Pulls](https://img.shields.io/docker/pulls/infocyph/llm-sm)
![Docker Image Size](https://img.shields.io/docker/image-size/infocyph/llm-sm)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Runtime: Ollama](https://img.shields.io/badge/Runtime-Ollama-black.svg)](https://ollama.com)

A self-contained local LLM image powered by Ollama.

The default image bakes `qwen2.5:3b` into the container during build, so it can start serving immediately without downloading model weights on first run.

## Registries and tags

CPU/NVIDIA and AMD ROCm variants are published in the same image repository.

| Registry | Image |
|---|---|
| Docker Hub | `docker.io/infocyph/llm-sm` |
| GitHub Container Registry | `ghcr.io/infocyph/llm-sm` |

For a release such as `v1.0.0`:

| Variant | Release tag | Moving tag |
|---|---|---|
| CPU / NVIDIA | `v1.0.0` | `latest` |
| AMD ROCm | `amd-v1.0.0` | `amd-latest` |

Release-version tags are immutable. Weekly scheduled builds refresh only `latest` and `amd-latest` against the current upstream Ollama bases.

## Defaults

| Setting | Default |
|---|---|
| Model | `qwen2.5:3b` |
| Ollama base | `ollama/ollama:latest` |
| API port | `11434` |
| Parallel requests | `1` |
| Loaded models | `1` |
| Keep alive | `5m` |
| Ollama cloud features | disabled |

`OLLAMA_NUM_PARALLEL=1` is intentionally conservative for local machines. Higher parallelism increases memory use and should be enabled only when the host has enough RAM/VRAM.

## Build

CPU or NVIDIA build:

```bash
docker build -t infocyph/llm-sm:local .
```

Build with another Ollama model:

```bash
docker build \
  --build-arg OLLAMA_MODEL=qwen2.5:1.5b \
  -t infocyph/llm-sm:local .
```

AMD ROCm build:

```bash
docker build \
  --build-arg OLLAMA_BASE_IMAGE=ollama/ollama:rocm \
  -t infocyph/llm-sm:amd-local .
```

The selected model is downloaded at build time and becomes part of the image. `OLLAMA_BASE_IMAGE` defaults to `ollama/ollama:latest`; AMD ROCm builds override it with `ollama/ollama:rocm`.

## Run

### CPU

```bash
docker run --rm \
  --name llm-sm \
  -p 127.0.0.1:11434:11434 \
  infocyph/llm-sm:local
```

### NVIDIA GPU

Install and configure the NVIDIA Container Toolkit on the host, then expose all NVIDIA GPUs with Docker's `--gpus` flag:

```bash
docker run --rm \
  --name llm-sm \
  --gpus=all \
  -p 127.0.0.1:11434:11434 \
  infocyph/llm-sm:local
```

The Docker flag is `--gpus=all` / `--gpus all` (plural), not `--gpu=all`.

### AMD GPU

```bash
docker run --rm \
  --name llm-sm \
  --device=/dev/kfd \
  --device=/dev/dri \
  -p 127.0.0.1:11434:11434 \
  infocyph/llm-sm:amd-local
```

AMD GPU support targets Linux hosts supported by Ollama/ROCm. If device permissions prevent GPU discovery, check the host permissions/group IDs for `/dev/kfd` and `/dev/dri` and add the required groups to the container.

The API is intentionally bound to localhost in these examples. Expose it to another interface only when you explicitly need network access and have appropriate network controls in place.

## Docker Compose

The repository's default `compose.yml` is the CPU-safe configuration:

```bash
cp .env.example .env
docker compose up --build -d
```

Ready-to-run examples are also provided under `examples/compose/`:

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
    build:
      context: .
      args:
        OLLAMA_BASE_IMAGE: ollama/ollama:latest
        OLLAMA_MODEL: ${OLLAMA_MODEL:-qwen2.5:3b}
    image: infocyph/llm-sm:local
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

Run the checked-in example from the repository root:

```bash
docker compose -f examples/compose/cpu.yml up --build -d
```

### NVIDIA GPU Compose

Docker Compose 2.30+ supports `gpus: all` directly:

```yaml
services:
  llm-sm:
    build:
      context: .
      args:
        OLLAMA_BASE_IMAGE: ollama/ollama:latest
        OLLAMA_MODEL: ${OLLAMA_MODEL:-qwen2.5:3b}
    image: infocyph/llm-sm:local
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

Run the checked-in example:

```bash
docker compose -f examples/compose/nvidia.yml up --build -d
```

For older Compose releases, the equivalent reservation syntax is:

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]
```

### AMD GPU Compose

AMD uses the ROCm Ollama base and Linux device passthrough rather than NVIDIA's `gpus: all` mechanism:

```yaml
services:
  llm-sm:
    build:
      context: .
      args:
        OLLAMA_BASE_IMAGE: ollama/ollama:rocm
        OLLAMA_MODEL: ${OLLAMA_MODEL:-qwen2.5:3b}
    image: infocyph/llm-sm:amd-local
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

Run the checked-in example:

```bash
docker compose -f examples/compose/amd.yml up --build -d
```

If AMD device permissions require explicit groups, determine the numeric group IDs on the host:

```bash
ls -lnd /dev/kfd /dev/dri /dev/dri/*
```

Then add the relevant IDs to the service, for example:

```yaml
group_add:
  - "44"
  - "109"
```

Do not copy those example IDs blindly; use the IDs reported by your host.

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

## Host CLI

The repository includes a modular Bash CLI for controlling the container and using the local model without repeatedly typing `docker exec` or raw API requests.

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

The default layout is:

```text
/usr/local/bin/llm-sm
/usr/local/lib/llm-sm/lib/
/usr/local/lib/llm-sm/commands/
/usr/local/lib/llm-sm/prompts/
```

A user-local installation keeps the same prefix layout:

```bash
./scripts/llm-sm install "$HOME/.local/bin"
```

which installs modules under `$HOME/.local/lib/llm-sm`.

Remove it with:

```bash
llm-sm uninstall
```

### Modular command layout

The entrypoint is intentionally small. Each command is implemented independently:

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

This keeps command behavior isolated while shared Docker/Ollama/input helpers and reusable prompts stay maintainable.

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

Generic prompt with a system-style instruction and file context:

```bash
llm-sm prompt \
  --system "Answer concisely and call out assumptions" \
  --file composer.json \
  "Explain this package architecture"
```

Generate or improve code:

```bash
llm-sm code "Write a lightweight PHP rate limiter"

llm-sm code \
  --file src/HotPath.php \
  "Optimize this hot path without changing behavior"
```

Piped code is accepted as context:

```bash
cat src/HotPath.php | llm-sm code "Optimize this implementation"
```

Review code:

```bash
llm-sm review src/Service.php
llm-sm review src/Service.php "Focus on concurrency and resource leaks"
cat src/Service.php | llm-sm review
```

`review` prioritizes correctness, security, performance, concurrency, resource handling, edge cases, compatibility risks, and production failure modes rather than style-only noise.

### AI commit

Generate a commit message from staged changes using the bundled Conventional Commit + Gitmoji prompt and the local Ollama model:

```bash
git add .
llm-sm ai-commit
```

The default flow prints the generated message and asks whether to commit, edit, or cancel.

Non-interactive options:

```bash
llm-sm ai-commit --print
llm-sm ai-commit --yes
llm-sm ai-commit --edit
llm-sm ai-commit -m qwen2.5:3b
```

The prompt is bundled at `scripts/prompts/ai-commit.txt`; this feature does not depend on Toolset, `gitx`, Gemini, or a network prompt source.

Use a different local prompt without modifying the installation:

```bash
LLM_SM_AI_COMMIT_PROMPT_FILE=/path/to/prompt.txt llm-sm ai-commit
```

### Structured JSON

Use Ollama's native JSON mode:

```bash
llm-sm json "Return an object with name and version"
```

The default output is the complete Ollama API response envelope and only requires `curl`.

To print only the model-produced JSON value, use `-r`/`--response-only`; that convenience mode requires `jq` on the host:

```bash
llm-sm json -r "Return an object with name and version"
```

A JSON Schema file can be supplied directly as Ollama's `format` value:

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

Raw Ollama commands remain available:

```bash
llm-sm ollama list
llm-sm ollama show qwen2.5:3b
```

And the HTTP API can be called without repeating the base URL:

```bash
llm-sm api /api/tags
```

The CLI defaults to container `llm-sm` and API `http://127.0.0.1:11434`. These can be overridden without editing scripts:

```bash
LLM_SM_CONTAINER=my-llm llm-sm status
LLM_SM_URL=http://127.0.0.1:12434 llm-sm api /api/tags
LLM_SM_MODEL=qwen2.5:1.5b llm-sm ask "Hello"
LLM_SM_SYSTEM="Be concise" llm-sm prompt "Explain CQRS"
```

`llm-sm pull` changes the writable layer of the current container. An additionally pulled model survives container stop/start but is lost when that container is removed or recreated. The model baked into the image remains the reproducible deployment model.

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

Build arguments:

| Argument | Purpose | Default |
|---|---|---|
| `OLLAMA_MODEL` | Model baked into the image | `qwen2.5:3b` |
| `OLLAMA_BASE_IMAGE` | Ollama runtime base image | `ollama/ollama:latest` |

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

Each GitHub Release builds both runtime variants in parallel and publishes them to the same image repository on Docker Hub and GHCR:

- CPU/NVIDIA: `<release>` and `latest`
- AMD ROCm: `amd-<release>` and `amd-latest`
- each variant has its own Buildx cache scope
- each pushed digest receives build provenance attestation
- weekly scheduled rebuilds check out the latest published release source and refresh only `latest` and `amd-latest`
- immutable release tags such as `v1.0.0` and `amd-v1.0.0` are never overwritten by scheduled builds

Required repository secrets:

```text
DOCKER_USERNAME
DOCKER_PASSWORD
```

GHCR authentication uses the repository `GITHUB_TOKEN`.

## Validation

The `CLI Check` workflow validates the host tooling on pull requests and `main`:

- `bash -n` across the entrypoint, libraries, and all command modules
- ShellCheck across all Bash files
- CPU/NVIDIA/AMD Compose configuration validation
- repository-layout smoke tests
- installed-layout smoke tests
- bundled `ai-commit` prompt validation
- idempotent reinstall
- uninstall cleanup

## License

MIT

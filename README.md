# 🤖 Local Small LLM Docker

[![Docker Publish](https://github.com/infocyph/docker-llm-sm/actions/workflows/docker.publish.yml/badge.svg)](https://github.com/infocyph/docker-llm-sm/actions/workflows/docker.publish.yml)
[![CLI Check](https://github.com/infocyph/docker-llm-sm/actions/workflows/cli.check.yml/badge.svg)](https://github.com/infocyph/docker-llm-sm/actions/workflows/cli.check.yml)
![Docker Pulls](https://img.shields.io/docker/pulls/infocyph/llm-sm)
![Docker Image Size](https://img.shields.io/docker/image-size/infocyph/llm-sm)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Runtime: Ollama](https://img.shields.io/badge/Runtime-Ollama-black.svg)](https://ollama.com)

A self-contained small local LLM runtime powered by Ollama.

The published image bakes `qwen2.5:3b` into the image so the service can start immediately without a first-run model download. The `llm-sm` CLI, command modules, and bundled prompts are also part of every published image. Users do not install or remove the CLI separately; models are the mutable part of the runtime.

## Published images

Consumers use published images only. Local image builds are not part of the supported usage flow.

| Registry | Repository |
|---|---|
| Docker Hub | `docker.io/infocyph/llm-sm` |
| GitHub Container Registry | `ghcr.io/infocyph/llm-sm` |

Two runtime variants are published through tags:

| Runtime | Moving tag | Release tag example |
|---|---|---|
| CPU / NVIDIA | `latest` | `v1.0.0` |
| AMD ROCm | `amd-latest` | `amd-v1.0.0` |

For reproducible deployments, pin a release tag rather than a moving tag.

## Defaults

| Setting | Default |
|---|---|
| Model | `qwen2.5:3b` |
| Persistent model volume | `llm-sm-data` |
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

Pinned release:

```bash
docker pull infocyph/llm-sm:v1.0.0
docker pull infocyph/llm-sm:amd-v1.0.0
```

## Persistent model state

`/root/.ollama` is mounted from the named Docker volume `llm-sm-data` by default. This keeps user-managed model state independent from the container lifecycle.

On first use, Docker creates the empty named volume and initializes it from the baked `/root/.ollama` contents in the image. The baked default model is therefore available immediately while the volume becomes the persistent model store afterward.

Models pulled or removed through `llm-sm` survive:

- container restart
- container stop/start
- `docker compose down` followed by `up`
- container recreation
- replacing the container with a newer image while reusing the same volume

The model store is removed only when the volume itself is explicitly removed, for example with `docker compose down -v` or `docker volume rm llm-sm-data`.

Use a different persistent model store by changing `LLM_SM_VOLUME`:

```bash
LLM_SM_VOLUME=my-models docker compose up -d
```

## Run

### CPU

```bash
docker run -d \
  --name llm-sm \
  --restart unless-stopped \
  -p 127.0.0.1:11434:11434 \
  --mount type=volume,src=llm-sm-data,dst=/root/.ollama \
  infocyph/llm-sm:latest
```

### NVIDIA GPU

```bash
docker run -d \
  --name llm-sm \
  --restart unless-stopped \
  --gpus=all \
  -p 127.0.0.1:11434:11434 \
  --mount type=volume,src=llm-sm-data,dst=/root/.ollama \
  infocyph/llm-sm:latest
```

### AMD GPU

```bash
docker run -d \
  --name llm-sm \
  --restart unless-stopped \
  --device=/dev/kfd \
  --device=/dev/dri \
  -p 127.0.0.1:11434:11434 \
  --mount type=volume,src=llm-sm-data,dst=/root/.ollama \
  infocyph/llm-sm:amd-latest
```

AMD GPU support targets Linux hosts supported by Ollama/ROCm. If device permissions prevent GPU discovery, inspect the host permissions/group IDs for `/dev/kfd` and `/dev/dri` and add the required groups to the container.

To use GHCR, replace `infocyph/llm-sm:<tag>` with `ghcr.io/infocyph/llm-sm:<tag>`.

The API is bound to localhost in these examples. Expose it to another interface only when explicitly required and protected appropriately.

## Repository-aware container

Commands such as `ai-commit`, file review, and code generation can work directly against a host repository by mounting that repository into the normal long-running `llm-sm` container.

From the project root:

```bash
docker run -d \
  --name llm-sm \
  --restart unless-stopped \
  -p 127.0.0.1:11434:11434 \
  --mount type=volume,src=llm-sm-data,dst=/root/.ollama \
  -v "$PWD:/workspace" \
  -w /workspace \
  infocyph/llm-sm:latest
```

For NVIDIA, add `--gpus=all`; for AMD use the `amd-*` image plus `/dev/kfd` and `/dev/dri` device mappings.

The workspace mount is a Docker runtime concern; the image does not manage or discover host directories itself. Docker cannot add a new bind mount to an already-created container, so mount the repository or a broader workspace directory when the container is created if repo-aware commands are needed.

Once mounted, keep using the same running container:

```bash
docker exec -it llm-sm llm-sm ai-commit
docker exec -it llm-sm llm-sm review src/Service.php
docker exec -it llm-sm llm-sm code -f src/HotPath.php "Optimize without changing behavior"
```

For read-only analysis, the repository can be mounted read-only:

```bash
-v "$PWD:/workspace:ro"
```

`ai-commit --yes` / `--edit` require a writable repository mount because Git must update repository state. If the container was created without a repository mount, use the stdin-diff fallback described below.

## Docker Compose

The default `compose.yml` consumes the published CPU/NVIDIA image and persists `/root/.ollama`:

```yaml
services:
  llm-sm:
    image: ${LLM_SM_IMAGE:-infocyph/llm-sm:latest}
    container_name: llm-sm
    restart: unless-stopped
    ports:
      - "127.0.0.1:${OLLAMA_PORT:-11434}:11434"
    volumes:
      - llm-sm-data:/root/.ollama
    environment:
      OLLAMA_NUM_PARALLEL: ${OLLAMA_NUM_PARALLEL:-1}
      OLLAMA_MAX_LOADED_MODELS: ${OLLAMA_MAX_LOADED_MODELS:-1}
      OLLAMA_KEEP_ALIVE: ${OLLAMA_KEEP_ALIVE:-5m}
      OLLAMA_NO_CLOUD: ${OLLAMA_NO_CLOUD:-1}

volumes:
  llm-sm-data:
    name: ${LLM_SM_VOLUME:-llm-sm-data}
```

Run it with:

```bash
docker compose pull
docker compose up -d
```

Ready-to-run examples are provided for each runtime:

```text
examples/compose/
├── cpu.yml
├── nvidia.yml
└── amd.yml
```

CPU:

```bash
docker compose -f examples/compose/cpu.yml pull
docker compose -f examples/compose/cpu.yml up -d
```

NVIDIA:

```bash
docker compose -f examples/compose/nvidia.yml pull
docker compose -f examples/compose/nvidia.yml up -d
```

AMD:

```bash
docker compose -f examples/compose/amd.yml pull
docker compose -f examples/compose/amd.yml up -d
```

For GHCR or pinned versions, override the image without editing the YAML:

```bash
LLM_SM_IMAGE=ghcr.io/infocyph/llm-sm:v1.0.0 \
  docker compose -f examples/compose/nvidia.yml up -d

LLM_SM_AMD_IMAGE=ghcr.io/infocyph/llm-sm:amd-v1.0.0 \
  docker compose -f examples/compose/amd.yml up -d
```

A repository/workspace mount can be added while keeping the model volume:

```yaml
services:
  llm-sm:
    volumes:
      - llm-sm-data:/root/.ollama
      - .:/workspace
    working_dir: /workspace

volumes:
  llm-sm-data:
    name: ${LLM_SM_VOLUME:-llm-sm-data}
```

## Bundled `llm-sm` CLI

`llm-sm` is part of every published image. There is no CLI install/uninstall command and no user-selectable module directory. The executable and all modules/prompts are versioned together with the image.

Published layout:

```text
/usr/local/bin/llm-sm
/usr/local/lib/llm-sm/
├── commands/
├── lib/
└── prompts/
```

Use it through the running container:

```bash
docker exec -it llm-sm llm-sm help
docker exec -it llm-sm llm-sm version
docker exec -it llm-sm llm-sm ask "Explain dependency injection briefly"
```

Interactive chat:

```bash
docker exec -it llm-sm llm-sm chat
```

For piped input, use `docker exec -i` without `-t`:

```bash
echo "Summarize this sentence" | docker exec -i llm-sm llm-sm ask
cat src/Service.php | docker exec -i llm-sm llm-sm review "Focus on correctness"
cat src/HotPath.php | docker exec -i llm-sm llm-sm code "Optimize without changing behavior"
```

### Model management

The CLI itself is fixed; models are user-managed persistent runtime state in `/root/.ollama`.

```bash
docker exec -it llm-sm llm-sm models
docker exec -it llm-sm llm-sm pull qwen2.5:1.5b
docker exec -it llm-sm llm-sm show qwen2.5:1.5b
docker exec -it llm-sm llm-sm run qwen2.5:1.5b "Hello"
docker exec -it llm-sm llm-sm unload qwen2.5:1.5b
docker exec -it llm-sm llm-sm rm qwen2.5:1.5b
```

Select a model per request:

```bash
docker exec -it llm-sm llm-sm ask -m qwen2.5:1.5b "Explain CQRS"
```

With the default `llm-sm-data` volume, model additions and removals survive container replacement. This lets users change the model set without changing or mutating the bundled CLI.

### Developer commands

Generic prompt:

```bash
echo "Explain this architecture" | \
  docker exec -i llm-sm llm-sm prompt --system "Answer concisely"
```

Code generation/rewrite with a mounted repository:

```bash
docker exec -it llm-sm \
  llm-sm code -f src/HotPath.php "Optimize this hot path without changing behavior"
```

Code review:

```bash
docker exec -it llm-sm \
  llm-sm review src/Service.php "Focus on concurrency and resource leaks"
```

Structured JSON:

```bash
docker exec -i llm-sm \
  llm-sm json -r "Return an object with name and version"
```

### AI commit

The Conventional Commit + Gitmoji prompt is bundled with the image.

With the current repository mounted at `/workspace`, the existing running container can read the staged Git diff directly:

```bash
git add .
docker exec -it llm-sm llm-sm ai-commit
```

Print only:

```bash
docker exec -it llm-sm llm-sm ai-commit --print
```

Commit immediately from the mounted repository:

```bash
docker exec -it llm-sm llm-sm ai-commit --yes
```

If the running container was created without a repository mount, send the staged diff through stdin instead:

```bash
git diff --cached | \
  docker exec -i llm-sm llm-sm ai-commit --diff-stdin
```

And, if desired, feed that generated message back to host Git:

```bash
git diff --cached | \
  docker exec -i llm-sm llm-sm ai-commit --diff-stdin | \
  git commit -F -
```

The feature is self-contained and does not depend on Toolset, `gitx`, Gemini, prompt caches, or a remote prompt source.

### CLI commands

| Command | Purpose |
|---|---|
| `llm-sm ask [-m model] <prompt>` | One-shot request |
| `llm-sm chat [model]` | Interactive model session |
| `llm-sm prompt [options] <prompt>` | Generic prompt with system/file/stdin context |
| `llm-sm code [options] <task>` | Generate or improve code |
| `llm-sm review [options] [file...] [focus]` | Review files or piped code |
| `llm-sm json [options] <prompt>` | Native structured JSON output |
| `llm-sm ai-commit [options]` | Generate/commit a message from Git changes |
| `llm-sm models` | List installed Ollama models |
| `llm-sm ps` | List loaded Ollama models |
| `llm-sm run <model> [prompt]` | Run an explicit model |
| `llm-sm show [model]` | Show model information |
| `llm-sm pull <model>` | Pull another model |
| `llm-sm rm <model>` | Remove a model |
| `llm-sm unload [model]` | Unload a model from RAM/VRAM |
| `llm-sm ollama <args...>` | Raw Ollama CLI passthrough |
| `llm-sm api <path> [curl args...]` | Raw HTTP API access |
| `llm-sm version` | CLI and Ollama versions |

Container lifecycle stays a Docker/Compose responsibility:

```bash
docker compose ps
docker compose logs -f llm-sm
docker compose restart llm-sm
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
  --mount type=volume,src=llm-sm-data,dst=/root/.ollama \
  -e OLLAMA_NUM_PARALLEL=2 \
  -e OLLAMA_KEEP_ALIVE=15m \
  infocyph/llm-sm:latest
```

## Model strategy

One small model is baked into each published image instead of being downloaded at container startup.

The image supplies the initial deterministic model state; the named volume supplies persistent user-managed state. This gives immediate first startup while allowing users to add, remove, or select other models without losing those changes when a container is replaced.

Advantages:

- deterministic release images
- immediate startup after image pull
- no first-run model download
- offline operation after the image is pulled
- persistent user-selected models
- fixed CLI/runtime tooling independent from mutable model data

## Publishing

Publishing is maintainer-managed by GitHub Actions. Consumers do not need the Dockerfile or a local build toolchain.

Each GitHub Release publishes into Docker Hub and GHCR:

- CPU/NVIDIA: `<release>` and `latest`
- AMD ROCm: `amd-<release>` and `amd-latest`
- immutable release tags are never changed by scheduled builds
- weekly scheduled builds refresh only `latest` and `amd-latest`
- both variants use separate Buildx cache scopes
- pushed digests receive provenance attestations

Required maintainer secrets:

```text
DOCKER_USERNAME
DOCKER_PASSWORD
```

GHCR publishing uses the repository `GITHUB_TOKEN`.

## Validation

The `CLI Check` workflow validates:

- Bash syntax and ShellCheck
- default/CPU/NVIDIA/AMD Compose definitions
- repository-layout CLI smoke tests
- bundled image-layout CLI smoke tests
- bundled `ai-commit` prompt availability
- absence of mutable CLI install/uninstall commands

## License

MIT

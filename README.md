# 🤖 Local Small LLM Docker

[![Docker Publish](https://github.com/infocyph/docker-llm-sm/actions/workflows/docker.publish.yml/badge.svg)](https://github.com/infocyph/docker-llm-sm/actions/workflows/docker.publish.yml)
[![CLI Check](https://github.com/infocyph/docker-llm-sm/actions/workflows/cli.check.yml/badge.svg)](https://github.com/infocyph/docker-llm-sm/actions/workflows/cli.check.yml)
![Docker Pulls](https://img.shields.io/docker/pulls/infocyph/llm-sm)
![Docker Image Size](https://img.shields.io/docker/image-size/infocyph/llm-sm)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Runtime: Ollama](https://img.shields.io/badge/Runtime-Ollama-black.svg)](https://ollama.com)

`docker-llm-sm` is a small local Ollama provider/runtime with a bundled developer CLI and a baked default model.

The image is intentionally provider-focused. It owns Ollama, model state, model-facing CLI commands and the local API. Container lifecycle, Nginx routing and higher-level AI features belong to Docker/Compose/LocalDevStack consumers.

## Runtime contract

| Item | Contract |
|---|---|
| Default model | `qwen2.5:3b` |
| Ollama API | `11434` inside the container |
| Model store | `/root/.ollama` |
| Default persistent volume | `llm-sm-data` |
| Standard image | CPU / NVIDIA |
| AMD image | separate ROCm `amd-*` tags |
| Runtime privacy | `OLLAMA_NO_CLOUD=1` |
| LocalDevStack internal URL | `http://llm-sm:11434` |
| LocalDevStack user URL | `https://llm.localhost` |

The standard image uses `ollama/ollama:latest`. The AMD image uses `ollama/ollama:rocm`. Publication resolves those moving upstream tags to a digest once per publish run so candidate validation and final publication use the same upstream bits.

## Published images

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

Release tags are immutable. Moving `latest` / `amd-latest` tags are refreshed from the latest published stable GitHub release.

Current publication remains `linux/amd64`. Standard `linux/arm64` will be published only after a native arm64 model/runtime gate exists; it is not claimed prematurely.

## Quick start with Docker Compose

```bash
docker compose pull
docker compose up -d
```

The default Compose service key is `llm-sm`, so Docker-network consumers can use:

```text
http://llm-sm:11434
```

The standalone Compose example binds the API only to localhost:

```text
127.0.0.1:11434
```

Useful lifecycle commands:

```bash
docker compose ps
docker compose logs -f llm-sm
docker compose restart llm-sm
docker compose down
```

Container lifecycle is intentionally not exposed through the `llm-sm` CLI.

## Persistent model state

The default Compose volume is:

```text
llm-sm-data -> /root/.ollama
```

A fresh empty Docker volume is populated from the image-baked model store, so `qwen2.5:3b` is available without a first-start model download.

User-pulled models survive container recreation and image replacement while the same volume is retained.

Use another model store when isolation is required:

```bash
LLM_SM_VOLUME=my-project-models docker compose up -d
```

The default `llm-sm-data` name is intentionally shared. Separate Compose projects using that default therefore reuse the same local model store. Set a distinct `LLM_SM_VOLUME` when projects must not share model state.

An existing populated volume is authoritative and hides the model store baked into a newer image. Upgrades never silently mutate that persistent store. If the requested model is absent, `llm-sm` returns an actionable error and the user can explicitly pull it.

## Optional Compose workspace mount

Repository-aware commands can use an optional Compose override rather than rebuilding the image:

```bash
LLM_SM_WORKSPACE="$PWD" \
  docker compose -f compose.yml -f compose.workspace.yml up -d
```

`compose.workspace.yml` mounts the workspace at `/workspace` and sets that as the working directory.

The mount is **read-only by default**:

```text
LLM_SM_WORKSPACE_MODE=ro
```

That is the recommended mode for analysis-only work:

```bash
docker compose -f compose.yml -f compose.workspace.yml \
  exec llm-sm llm-sm review src/Service.php

docker compose -f compose.yml -f compose.workspace.yml \
  exec llm-sm llm-sm code -f src/HotPath.php "Optimize without changing behavior"

docker compose -f compose.yml -f compose.workspace.yml \
  exec llm-sm llm-sm ai-commit --print
```

For commands that intentionally mutate Git state, opt into a writable workspace:

```bash
LLM_SM_WORKSPACE="$PWD" LLM_SM_WORKSPACE_MODE=rw \
  docker compose -f compose.yml -f compose.workspace.yml up -d

docker compose -f compose.yml -f compose.workspace.yml \
  exec llm-sm llm-sm ai-commit --yes
```

The workspace mount is optional and independent from the persistent `/root/.ollama` model volume. The image never scans or mounts host repositories automatically.

When combining `compose.workspace.yml` with files under `examples/compose/`, set `LLM_SM_WORKSPACE` to an absolute path such as `$PWD` so the intended repository is mounted.

## Runtime variants

Ready-to-run Compose files are provided under `examples/compose/`:

```text
examples/compose/
├── cpu.yml
├── nvidia.yml
└── amd.yml
```

CPU:

```bash
docker compose -f examples/compose/cpu.yml up -d
```

NVIDIA:

```bash
docker compose -f examples/compose/nvidia.yml up -d
```

AMD ROCm:

```bash
docker compose -f examples/compose/amd.yml up -d
```

The NVIDIA path uses the standard image. The AMD path uses `amd-latest` and exposes `/dev/kfd` plus `/dev/dri` as required by the ROCm runtime.

## Standalone `docker run`

CPU:

```bash
docker run -d \
  --name llm-sm \
  --restart unless-stopped \
  -p 127.0.0.1:11434:11434 \
  --mount type=volume,src=llm-sm-data,dst=/root/.ollama \
  infocyph/llm-sm:latest
```

NVIDIA adds:

```text
--gpus=all
```

AMD uses `infocyph/llm-sm:amd-latest` plus:

```text
--device=/dev/kfd
--device=/dev/dri
```

For a standalone repository-aware container, add a bind mount and working directory when creating it:

```bash
docker run -d \
  --name llm-sm \
  --restart unless-stopped \
  -p 127.0.0.1:11434:11434 \
  --mount type=volume,src=llm-sm-data,dst=/root/.ollama \
  --mount type=bind,src="$PWD",dst=/workspace,readonly \
  -w /workspace \
  infocyph/llm-sm:latest
```

The explicit `--name llm-sm` is appropriate for this standalone `docker run` flow. Compose intentionally does not set `container_name`.

## Bundled `llm-sm` CLI

The CLI is fixed image content. Models remain mutable persistent runtime state.

Main command groups:

```text
Developer: ask, chat, prompt, code, review, json, ai-commit
Model:     models, ps, run, show, pull, rm, unload
Low level: ollama, api, version
```

With Compose:

```bash
docker compose exec llm-sm llm-sm help
docker compose exec llm-sm llm-sm version
docker compose exec llm-sm llm-sm models
docker compose exec llm-sm llm-sm ask "Explain dependency injection briefly"
```

Model management is explicit:

```bash
docker compose exec llm-sm llm-sm pull qwen2.5:1.5b
docker compose exec llm-sm llm-sm show qwen2.5:1.5b
docker compose exec llm-sm llm-sm run qwen2.5:1.5b "Hello"
docker compose exec llm-sm llm-sm rm qwen2.5:1.5b
```

The CLI does not silently pull a missing model when another command selects it.

### Attachments and multimodal prompts

`llm-sm prompt` accepts normal text context, large piped input, images and PDFs.

Auto-detect a text file, image or PDF from its extension:

```bash
docker compose exec llm-sm \
  llm-sm prompt --attach /workspace/notes.txt "Summarize this"
```

Use an image with a vision-capable model:

```bash
docker compose exec llm-sm llm-sm pull qwen2.5vl:3b

docker compose exec llm-sm \
  llm-sm prompt -m qwen2.5vl:3b \
  --image /workspace/diagram.png \
  "Explain this architecture diagram"
```

The baked `qwen2.5:3b` model remains the lightweight text default. The CLI never silently switches models or downloads a vision model. When image input is requested, the selected model must report Ollama's `vision` capability.

For text-based PDFs, extract text locally and send it as normal context:

```bash
docker compose exec llm-sm \
  llm-sm prompt --pdf /workspace/spec.pdf "Summarize the important requirements"
```

For scanned PDFs, diagrams, forms or layouts where the page image matters, render the PDF pages and send them to a vision model:

```bash
docker compose exec llm-sm \
  llm-sm prompt -m qwen2.5vl:3b \
  --pdf-vision /workspace/scanned-spec.pdf \
  "Read and summarize this document"
```

`LLM_SM_PDF_DPI` controls page rendering and defaults to `120`. PDF text extraction/rendering is provided by the image's `poppler-utils` runtime dependency.

Multiple `--attach`, `--image`, `--pdf` and `--pdf-vision` options can be supplied in one request.

### Structured JSON

```bash
docker compose exec llm-sm \
  llm-sm json -r "Return an object with name and version"
```

JSON Schema files are validated locally before a request is sent.

### AI commit

With a workspace mount:

```bash
git add .
docker compose -f compose.yml -f compose.workspace.yml \
  exec llm-sm llm-sm ai-commit --print
```

Without a repository mount, send the staged diff through stdin:

```bash
git diff --cached | \
  docker compose exec -T llm-sm llm-sm ai-commit --diff-stdin
```

## Large-input behavior

Large text, files and Git diffs are accepted by default. The CLI warns rather than rejects when context becomes unusually large.

Defaults:

```text
LLM_SM_INPUT_WARN_BYTES=1048576
LLM_SM_INPUT_MAX_BYTES=0
```

`LLM_SM_INPUT_MAX_BYTES=0` means no CLI hard ceiling. The effective useful size is still bounded by the selected model's context window, Ollama/runtime memory and available host RAM/VRAM.

To impose a local policy ceiling, set a non-zero maximum:

```bash
LLM_SM_INPUT_MAX_BYTES=4194304
```

If a non-zero ceiling is configured, `LLM_SM_ALLOW_LARGE_INPUT=1` can explicitly bypass it for a deliberate request. Input is never silently truncated by `llm-sm`.

Large request bodies are built through temporary files and `jq --rawfile`/file-backed `curl` payloads rather than shell command-line arguments, avoiding normal shell argv-size limits for large diffs and document text.

The byte guard is intentionally approximate; it does not pretend to provide exact tokenizer accounting for arbitrary models.

## Native Ollama API

List models:

```bash
curl http://127.0.0.1:11434/api/tags
```

Non-streaming generation:

```bash
curl http://127.0.0.1:11434/api/generate \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen2.5:3b","prompt":"Reply with OK only.","stream":false}'
```

Ollama's supported OpenAI-compatible `/v1/...` endpoints are exposed directly as well.

No proprietary provider API is added by this project.

## LocalDevStack integration

The provider contract is:

```text
service:  llm-sm
internal: http://llm-sm:11434
external: https://llm.localhost
```

Internal Docker consumers should use `http://llm-sm:11434` directly. They should not route service-to-service traffic through Nginx.

Nginx owns the optional user-facing HTTPS route. LocalDevStack can omit the direct host `11434` mapping entirely and expose only `443` while keeping `llm-sm:11434` available on the internal network.

The broader stack must remain usable when `llm-sm` is disabled or absent. Consumer-specific AI behavior belongs in those consumers, not in this image.

## Privacy and exposure

Runtime defaults are intentionally local:

- `OLLAMA_NO_CLOUD=1`
- no external AI fallback added by this project
- no telemetry layer added by this project
- no Docker socket required
- no automatic repository ingestion
- no wildcard CORS policy enabled by default
- standalone examples bind `11434` to `127.0.0.1`

If a browser client needs direct access, configure explicit `OLLAMA_ORIGINS` values rather than enabling wildcard CORS.

## Optional upstream tuning

Conservative defaults remain:

```text
OLLAMA_NUM_PARALLEL=1
OLLAMA_MAX_LOADED_MODELS=1
OLLAMA_KEEP_ALIVE=5m
```

Additional upstream settings such as `OLLAMA_CONTEXT_LENGTH`, `OLLAMA_MAX_QUEUE`, `OLLAMA_LOAD_TIMEOUT` and `OLLAMA_ORIGINS` can be passed when a real deployment needs them. Larger context and parallelism increase RAM/VRAM pressure.

For outbound model pulls behind a proxy, prefer `HTTPS_PROXY`. Do not set `HTTP_PROXY` blindly because it can interfere with normal Ollama client/server communication.

## Validation and release safety

Lightweight CI validates Bash/ShellCheck, command registry, model-selection precedence, structured JSON handling, input guards, Compose contracts and Dockerfile structure without downloading the 3B model on every PR.

The reusable `Runtime Check` performs the real model-bearing standard-image gate, including:

- fresh-volume baked-model presence
- daemon health
- PDF text/render tooling availability
- non-streaming generation
- streaming chat
- bundled CLI inference
- missing-model behavior
- persistent-volume recreation
- SIGTERM shutdown and OOM state

Publication additionally:

- resolves latest stable release source explicitly
- prevents prereleases from moving stable `latest` tags
- protects immutable release tags in Docker Hub and GHCR
- resolves each moving Ollama base to one digest for the whole publish run
- validates the standard runtime before publication
- enables BuildKit provenance and SBOM
- verifies both registries resolve the pushed digest
- verifies the published platform as `linux/amd64`

## License

MIT

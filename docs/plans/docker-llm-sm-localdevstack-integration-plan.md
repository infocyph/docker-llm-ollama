# docker-llm-sm — LocalDevStack Provider Integration & Hardening Plan

## Status

Planning branch: `plan/docker-llm-sm-integration`

Baseline:

- Repository: `infocyph/docker-llm-sm`
- Default branch: `main`
- Current published release: `0.01`
- Runtime: Ollama
- Default bundled model: `qwen2.5:3b`
- Standard image base: `ollama/ollama:latest`
- AMD image base: `ollama/ollama:rocm`
- Published image role: small local LLM provider/runtime
- LocalDevStack consumer: `docker-tools`
- User-facing Nginx route: `https://llm.localhost`
- Internal Docker endpoint: `http://llm-sm:11434`

This plan is intentionally provider-focused. AI use cases, copilots, log explanations, code/repo assistance and other higher-level intelligence belong in `docker-tools`, not here.

---

# 1. Goal

Make `docker-llm-sm` a stable, persistent, LocalDevStack-ready AI provider that other containers can consume without duplicating Ollama or model lifecycle responsibilities.

The image should continue to provide:

1. a ready-to-use Ollama API;
2. a small baked default model;
3. persistent user-managed model state;
4. CPU/NVIDIA and AMD ROCm publication variants;
5. the fixed bundled `llm-sm` developer CLI;
6. predictable Docker/network/API contracts for LocalDevStack consumers.

It should not become a LocalDevStack control plane.

---

# 2. Architecture invariants

Preserve these decisions:

- Consumers use published images only; no consumer-side image build workflow.
- Standard image handles CPU/NVIDIA through `ollama/ollama:latest`.
- AMD uses the separate `ollama/ollama:rocm` base and `amd-*` tags.
- `qwen2.5:3b` remains the default small model unless changed deliberately.
- Users may pull/remove/use other models at runtime.
- `/root/.ollama` is persistent mutable state.
- CLI commands/modules/prompts are fixed image capabilities, not user-installed plugins.
- Container lifecycle is Docker/Compose/LocalDevStack responsibility.
- Model lifecycle is Ollama/`llm-sm` responsibility.
- `OLLAMA_NO_CLOUD=1` remains the runtime privacy default.
- `llm-sm` listens on container port `11434`.
- LocalDevStack internal consumers use Docker DNS: `http://llm-sm:11434`.
- Browser/user-facing traffic goes through Nginx at `https://llm.localhost` when the LocalDevStack AI service is enabled.

---

# 3. LocalDevStack integration contract

## 3.1 Service identity

LocalDevStack should create the service with the stable Compose service name:

```text
llm-sm
```

That makes the internal provider URL deterministic:

```text
http://llm-sm:11434
```

`docker-tools` should use this internal URL rather than routing container-to-container requests through Nginx.

## 3.2 User-facing route

Nginx 0.4.1+ owns:

```text
llm.localhost -> llm-sm:11434
```

with streaming-safe proxy behavior.

Expected user-facing endpoints include:

```text
https://llm.localhost/api/chat
https://llm.localhost/api/generate
https://llm.localhost/api/tags
https://llm.localhost/v1/...
```

Do not add Nginx into this image.

## 3.3 Optional service behavior

The LocalDevStack stack must remain usable when `llm-sm` is disabled or absent.

Consumers such as `docker-tools` should detect availability and degrade cleanly.

`docker-llm-sm` itself does not need awareness of whether Tools, Graphify or any other consumer exists.

---

# 4. Persistence contract

Current persistent path:

```text
/root/.ollama
```

Current named volume default:

```text
llm-sm-data
```

Preserve:

```yaml
volumes:
  - llm-sm-data:/root/.ollama
```

and the `LLM_SM_VOLUME` override.

Expected behavior:

- first empty volume is initialized from image-baked `/root/.ollama` contents by Docker's normal volume population behavior;
- default baked model is therefore available on fresh install;
- user-pulled models persist across restart, stop/start, Compose down/up, container recreation and image replacement while the same volume is retained;
- explicit volume deletion removes persistent model state.

## Existing-volume upgrade caveat

When an existing populated volume is mounted, it becomes authoritative and hides the image's baked `/root/.ollama` directory.

Therefore, if a future release changes the baked default model, existing installations will not automatically receive that new baked model.

Do not silently mutate users' persistent model stores.

For now:

- document this behavior;
- keep upgrades non-destructive;
- add an explicit opt-in `pull`/ensure workflow later only if needed.

---

# 5. Dockerfile hardening

## `Dockerfile`

Plan:

1. Keep `ARG OLLAMA_BASE_IMAGE` so the same Dockerfile can build standard and ROCm variants.
2. Continue using upstream Ollama images rather than rebuilding Ollama.
3. Keep only runtime packages actually needed by bundled CLI (`curl`, `git`, `jq`).
4. Preserve fixed CLI copy into `/usr/local/bin/llm-sm` and `/usr/local/lib/llm-sm`.
5. Keep model bake during image construction so published images are immediately useful offline after pull.
6. Keep build-time `OLLAMA_NO_CLOUD=0` scoped only to model acquisition and runtime default `OLLAMA_NO_CLOUD=1`.
7. Bound Ollama startup readiness during build and print useful server logs on failure.
8. Verify the baked model with both `ollama show` and an API/model-list contract where practical.
9. Keep port `11434` only.
10. Keep upstream Ollama as PID 1 via `/bin/ollama serve`.
11. Keep healthcheck independent of the `llm-sm` wrapper; health should prove Ollama itself is ready.
12. Record upstream base/model/runtime resolution in publication summaries.
13. Do not add LocalDevStack, Nginx, Tools, Graphify or other consumer packages into this image.

---

# 6. CLI responsibility cleanup

The current published tree still contains legacy host-side lifecycle commands such as:

```text
scripts/commands/start.sh
scripts/commands/stop.sh
scripts/commands/restart.sh
scripts/commands/status.sh
scripts/commands/logs.sh
```

and Docker-host helper functions in `scripts/lib/docker.sh`.

These conflict with the settled product contract that Docker/Compose/LocalDevStack owns container lifecycle.

Plan:

- remove host lifecycle commands from the image/CLI command surface;
- remove obsolete Docker-inspection/container-control helpers after checking remaining call sites;
- keep only model/API/developer commands that make sense inside the published image;
- preserve repository-aware developer commands such as `ai-commit`, `review`, `code`, `ask`, `prompt`, `json`;
- preserve mounted-workspace support;
- keep `git -c safe.directory='*'` process-local handling for mounted repositories;
- do not require Docker socket access inside `llm-sm`.

Desired final command classes:

```text
Developer: ask, chat, prompt, code, review, json, ai-commit
Model: models, ps, run, show, pull, rm, unload
Low-level: ollama, api, version
```

---

# 7. Consumer API contract

Consumers should be able to rely on standard Ollama APIs directly.

Minimum compatibility gates:

- `GET /api/tags`;
- `POST /api/generate`;
- `POST /api/chat`;
- OpenAI-compatible `/v1/...` endpoints supported by upstream Ollama;
- streamed and non-streamed responses;
- model override per request;
- long-running request handling without premature server termination.

Do not add a proprietary wrapper API unless a real incompatibility appears.

`docker-tools` should consume Ollama directly through its own provider abstraction.

---

# 8. Graphify and other consumers

No Graphify-specific package/code belongs in this image.

The provider contract should simply allow external consumers to point to:

```text
http://llm-sm:11434/v1
```

inside Docker or:

```text
https://llm.localhost/v1
```

through LocalDevStack Nginx when appropriate.

Keep the provider generic enough for future local consumers without adding consumer-specific dependencies.

---

# 9. Compose examples

## `compose.yml`

Keep this repository's standalone example simple:

- published image only;
- localhost-bound direct port for standalone use;
- persistent `llm-sm-data` volume;
- existing concurrency/keep-alive/cloud settings.

LocalDevStack integration may omit direct host port `11434` and rely on Nginx `443` plus Docker-internal `11434`.

That is an orchestration decision and should not force standalone examples to change unnecessarily.

## `examples/compose/cpu.yml`

- keep standard image;
- keep persistence;
- smoke-test API readiness.

## `examples/compose/nvidia.yml`

- keep standard image plus GPU reservation/device contract;
- validate against current Docker GPU syntax;
- keep same persistence/API contract.

## `examples/compose/amd.yml`

- keep `amd-latest` image family;
- preserve ROCm device/group requirements;
- validate against current upstream Ollama ROCm guidance;
- keep same persistence/API contract.

---

# 10. CI hardening

Current CLI validation is useful but does not fully prove the published runtime.

Add/expand permanent gates:

## Lightweight PR gates

- Bash syntax;
- ShellCheck;
- command registry/help contract;
- no legacy host lifecycle commands;
- Compose interpolation/config checks;
- persistent volume contract;
- standard/AMD tag convention checks;
- no Docker socket requirement;
- no consumer-specific packages.

## Runtime smoke gates

Because model-bearing image builds are large, keep CI deliberate but real.

At least before release:

1. build/pull standard candidate;
2. start Ollama;
3. wait for health;
4. verify `/api/tags` contains a model;
5. run a tiny non-streaming generate request;
6. run a tiny streaming generate/chat request;
7. run one bundled CLI request;
8. validate persistent model state with volume recreate cycle;
9. verify clean SIGTERM shutdown.

For ROCm, CI may validate build/manifest/config where GPU hardware is unavailable, with real ROCm runtime validation performed only on an appropriate runner if later available.

Do not download a second large model merely for CI.

---

# 11. Publication workflow

Preserve the good architecture already established:

- Docker Hub + GHCR;
- standard tag family: `<release>`, `latest`;
- AMD tag family: `amd-<release>`, `amd-latest`;
- release publishes immutable release tags plus moving latest tags;
- scheduled refresh updates only moving tags;
- standard and AMD variants built from their correct upstream Ollama bases;
- provenance attestations.

Further hardening:

- explicit immutable-tag existence guard;
- current Action majors;
- concurrency and timeout;
- variant-scoped cache;
- SBOM where practical;
- post-publish manifest verification;
- record resolved Ollama upstream/base digest and baked model metadata in workflow summary;
- verify both registries resolve to expected manifests.

Do not merge standard + ROCm into one image. Upstream Ollama publishes ROCm separately and our tag families should mirror that architectural split.

---

# 12. Privacy/security rules

- runtime `OLLAMA_NO_CLOUD=1` by default;
- no external AI-provider fallback inside this image;
- no telemetry layer added by us;
- no Docker socket mount requirement;
- no automatic repository/file ingestion;
- mounted workspace access occurs only when user/LocalDevStack explicitly mounts it;
- model output is never executed automatically;
- API exposure is controlled by orchestration/Nginx, not by adding authentication logic ad hoc here;
- avoid broad CORS changes unless a concrete browser-client requirement is defined.

---

# 13. Documentation updates

## `README.md`

Reconcile around two supported modes:

### Standalone

```text
127.0.0.1:11434
```

### LocalDevStack

```text
internal: http://llm-sm:11434
external: https://llm.localhost
```

Document:

- persistent model volume;
- standard vs AMD image tags;
- fixed CLI vs mutable models;
- default 3B model rationale;
- workspace mounting for developer commands;
- model-store upgrade caveat;
- no consumer local builds;
- container lifecycle belongs to Docker/LocalDevStack.

---

# 14. LocalDevStack compatibility gate

Before treating the integration as complete, prove:

1. LocalDevStack can start `llm-sm` as an optional service.
2. Nginx 0.4.1+ routes `llm.localhost` correctly.
3. streaming `/api/chat` and `/api/generate` work through Nginx.
4. `docker-tools` can reach `http://llm-sm:11434` by Docker DNS.
5. Tools works normally when `llm-sm` is absent.
6. model state persists through container recreation.
7. direct host port `11434` is not required by Tools-to-LLM communication.
8. no static IP is required.

---

# 15. Acceptance criteria

Provider integration is ready when:

1. CLI/static CI is green;
2. legacy host lifecycle command surface is removed;
3. standard image runtime smoke passes;
4. default model is available immediately in a fresh image/volume;
5. model persistence survives recreation;
6. generate/chat streaming and non-streaming APIs pass;
7. `docker-tools` can consume the provider at `http://llm-sm:11434`;
8. `https://llm.localhost` works through Nginx;
9. standard CPU/NVIDIA and AMD ROCm tag families remain separate;
10. release tags are immutable and schedules refresh only moving tags;
11. provider remains usable independently of LocalDevStack;
12. no higher-level Tools AI feature is implemented here.

---

# 16. Recommended implementation order

1. Remove obsolete host lifecycle CLI code.
2. Expand lightweight CI contracts.
3. Add real standard-image API/runtime smoke validation.
4. Add persistent-volume recreation test.
5. Harden publication/manifest verification.
6. Validate LocalDevStack Nginx + Tools interoperability.
7. Reconcile README/examples.
8. Publish the next provider release only after the LocalDevStack compatibility gate passes.

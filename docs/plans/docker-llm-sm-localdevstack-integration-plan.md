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

---

# 17. Additive full-repository review findings

Everything below is additive to Sections 1–16. If an item below ever conflicts with an earlier invariant or hard requirement, Sections 1–16 win.

The planning branch currently changes only this plan file, so the implementation baseline remains the current `main` codebase. The following items come from reviewing that full baseline rather than only the integration draft.

## 17.1 Keep the CLI image-native after lifecycle cleanup

The final production CLI should be conceptually image-native:

- `docker exec ... llm-sm ...` for a manually named standalone container;
- `docker compose exec llm-sm llm-sm ...` when Compose owns the service;
- direct `llm-sm ...` from inside another explicitly designed execution context only when the bundled runtime files are actually present.

Do not retain Docker-host control logic merely to preserve historical source-tree convenience.

When removing lifecycle commands:

- remove `start`, `stop`, `restart`, `status` and `logs` modules;
- remove their help entries and tests;
- inspect all remaining call sites before deleting `scripts/lib/docker.sh`;
- move genuinely model-related helpers out of Docker-specific code when still needed;
- make the final bundled CLI independent of the Docker CLI and Docker socket.

Repository-source invocation can remain a CI/developer convenience, but it must not drive the production architecture.

## 17.2 Unify default-model resolution

All model-consuming commands must use one resolver with this precedence:

```text
explicit command option
-> LLM_SM_MODEL
-> OLLAMA_MODEL
-> baked fallback (qwen2.5:3b)
```

The current `json` command has a divergent path and can fall back to `qwen2.5:3b` inside the image instead of honoring `OLLAMA_MODEL`/`LLM_SM_MODEL`.

Plan:

- centralize model resolution in one helper;
- make `ask`, `chat`, `prompt`, `code`, `review`, `json`, `show`, `unload` and future model-aware commands use it;
- test each precedence level explicitly;
- never auto-pull a missing model as a side effect of resolving a default;
- when the selected model is absent, return an actionable error that points to `llm-sm pull <model>`.

This is especially important because an existing persistent volume can legitimately hide the image-baked model.

## 17.3 Stop hand-building JSON where `jq` is already mandatory

`jq` is already installed as a fixed runtime dependency and is already used by `ai-commit`.

Use it consistently for request payload generation:

- replace hand-written string escaping/payload concatenation where practical with `jq -n` + `--arg` / `--argjson`;
- validate `json --schema <file>` as valid JSON before sending it;
- compact schema JSON before embedding it;
- fail locally with a clear message for malformed schema input;
- remove `json_quote()` if no call site remains afterward.

Keep generation requests free of a short total request timeout because local inference may legitimately run for a long time. A small connect timeout may be used to fail quickly when the daemon is unavailable.

## 17.4 Bound accidental context explosions

Developer commands can currently feed arbitrary files, piped content and Git diffs into a small local model. This is useful, but accidental multi-megabyte input creates poor latency, memory pressure and low-quality truncation behavior.

Add a common preflight input-budget mechanism for `prompt`, `code`, `review` and `ai-commit`:

- measure input bytes before inference;
- provide a conservative configurable soft limit;
- warn clearly when input is unusually large;
- provide a bounded hard safety limit unless explicitly overridden;
- never silently truncate repository content or diffs;
- print enough guidance for the user to narrow files/diffs when rejected.

Prefer byte-based guarding in the shell rather than pretending to perform exact tokenizer accounting for every model.

## 17.5 Benchmark the bundled `ai-commit` prompt

The `ai-commit` prompt is intentionally detailed, but its current size is significant relative to a small 3B model and every invocation pays that context cost.

Before release:

- benchmark current prompt latency and output quality against a reduced equivalent;
- remove redundant prose or duplicated guidance only where output quality does not regress;
- preserve the required Conventional Commit + Gitmoji contract;
- do not remove rules merely to reduce file size;
- keep the prompt bundled and versioned with the image.

Treat this as a performance/QoL optimization, not as a functional rewrite.

---

# 18. Compose and developer-experience hardening

## 18.1 Remove fixed `container_name` from Compose files

The Compose service name already provides stable Docker DNS as `llm-sm`.

Hard-coding:

```yaml
container_name: llm-sm
```

is unnecessary and prevents multiple independent Compose projects from running the service concurrently.

Plan:

- remove `container_name` from `compose.yml` and all `examples/compose/*.yml` files;
- keep the service key exactly `llm-sm` so the internal endpoint remains `http://llm-sm:11434`;
- update Compose-oriented documentation to prefer `docker compose exec llm-sm ...`;
- keep `--name llm-sm` only in explicit standalone `docker run` examples where the user intentionally owns that global name.

This must not alter the LocalDevStack service identity or internal endpoint contract.

## 18.2 Make shared-volume behavior explicit

The explicit named-volume contract remains:

```text
llm-sm-data
```

with `LLM_SM_VOLUME` override.

Because the volume has an explicit global name, separate Compose projects using the default will intentionally share the same model store.

Document that clearly:

- default = reusable shared local model cache/store;
- isolated stack = set a distinct `LLM_SM_VOLUME`;
- never silently namespace or rename the existing default volume because persistence is a hard contract.

## 18.3 Expose useful upstream tuning without changing defaults

Keep the current conservative defaults for small local systems:

```text
OLLAMA_NUM_PARALLEL=1
OLLAMA_MAX_LOADED_MODELS=1
OLLAMA_KEEP_ALIVE=5m
```

Do not raise them automatically.

Document optional pass-through tuning only where useful, including current upstream knobs such as:

```text
OLLAMA_CONTEXT_LENGTH
OLLAMA_MAX_QUEUE
OLLAMA_LOAD_TIMEOUT
OLLAMA_ORIGINS
```

Rules:

- do not set these merely because upstream supports them;
- explain that parallelism/context increases RAM/VRAM requirements;
- never use a wildcard CORS origin by default;
- expose an environment variable in examples only when there is a real LocalDevStack/user need.

## 18.4 Proxy/certificate QoL

For environments that need outbound proxying during model pulls:

- document `HTTPS_PROXY` support;
- do not set `HTTP_PROXY` by default because it can interfere with normal Ollama client/server communication;
- document custom CA injection only as an advanced deployment concern;
- keep proxy credentials and certificates outside the image/repository.

---

# 19. Platform and GPU publication strategy

## 19.1 Add standard-image multi-arch support deliberately

The upstream standard Ollama image currently provides both `linux/amd64` and `linux/arm64`, while the ROCm image remains a separate AMD-oriented `linux/amd64` path.

The current workflow does not specify `platforms`, so publication effectively follows the GitHub runner architecture.

Plan for the standard tag family:

```text
linux/amd64
linux/arm64
```

but only advertise/publish both after the complete model-bake and runtime smoke contract passes on each architecture.

Important constraints:

- do not make slow/emulated Ollama inference under QEMU the permanent release strategy merely to claim multi-arch;
- prefer native architecture builders/runners where feasible;
- if a reliable build-only cross-architecture approach is used, separately prove that the resulting arm64 runtime starts and serves the baked model natively;
- keep a manifest gate that verifies the advertised standard platforms.

If arm64 cannot yet satisfy the full release gate, publish only the proven architecture and do not claim arm64 support prematurely.

## 19.2 Keep ROCm architecture separate

Preserve the hard variant split:

```text
standard: latest / <release>
ROCm:     amd-latest / amd-<release>
```

Do not merge ROCm into the standard manifest.

Until upstream support and real runners prove otherwise:

- treat the ROCm tag family as `linux/amd64`;
- validate `/dev/kfd` + `/dev/dri` guidance against current upstream requirements;
- do not claim ROCm runtime validation from a CPU-only CI runner.

## 19.3 Do not silently broaden GPU claims

Upstream capabilities may evolve independently of this project. New Vulkan, Jetson or other acceleration paths should be treated as separate compatibility work:

- no automatic support claim merely because the upstream base contains code for it;
- add a documented runtime path only after a real smoke test and maintenance contract exist;
- keep CPU/NVIDIA standard + AMD ROCm as the supported baseline for this plan.

---

# 20. Moving-upstream-base hardening

The hard plan intentionally keeps moving upstream bases:

```text
ollama/ollama:latest
ollama/ollama:rocm
```

That gives users current Ollama improvements, but it also makes upstream drift part of the release risk.

Add compensating controls rather than pinning away the requirement.

## 20.1 Preflight upstream compatibility

Before a release/scheduled rebuild is accepted, prove that the selected upstream base still provides the assumptions used here:

- `/bin/ollama` exists and executes;
- expected package-management path still supports the minimal CLI dependencies, or installation logic is adjusted deliberately;
- `/root/.ollama` remains the expected model store for this image contract;
- `ollama serve`, `ollama list`, `ollama pull` and `ollama show` work as expected;
- healthcheck command remains valid.

Do not add an OS-wide package upgrade step.

## 20.2 Record resolved build identity

For every published variant, record in the workflow summary and/or OCI metadata where practical:

- target platform;
- resolved upstream base digest;
- `ollama --version`;
- configured default model reference;
- baked model metadata/digest available from Ollama;
- resulting published image digest.

This makes a moving-base rebuild auditable without changing the moving-base policy.

## 20.3 Separate daemon health from model completeness

Keep the container healthcheck focused on daemon readiness.

Do not make health depend on the baked default model because an existing populated volume can legitimately replace the image's baked `/root/.ollama` state.

Instead:

- release/runtime smoke should separately verify the baked model on a fresh volume;
- healthcheck should prove the Ollama daemon responds;
- `llm-sm` commands should give a useful missing-model error when a user-managed volume lacks the requested model.

## 20.4 Bound expensive build stages

The model-bearing build is intentionally large and network-sensitive.

Add:

- workflow/job timeout bounds;
- bounded daemon-start readiness as already planned;
- useful build-log output when model pull fails;
- no duplicate model download inside the same CI path when avoidable;
- cache usage that does not accidentally turn an immutable release into stale/unverified model state.

---

# 21. CLI/version contract and lightweight regression tests

## 21.1 Eliminate duplicated version literals

The repository currently carries CLI version expectations in more than one place.

Move toward one authoritative version source for the bundled CLI and make CI derive its assertion from that source.

Requirements:

- `llm-sm version` must remain cheap and deterministic;
- CI must not hard-code the same version separately in multiple commands;
- publication should record the bundled CLI version;
- define release-tag-to-CLI-version validation deliberately rather than assuming historical release `0.01` already follows the newer CLI numbering scheme.

Do not rewrite existing release history simply to normalize version syntax.

## 21.2 Add shell-level behavior tests

Without downloading a model, lightweight CI should prove at least:

- every public command has a valid module;
- help and command registry agree;
- removed lifecycle commands cannot reappear unnoticed;
- default-model precedence is correct;
- malformed JSON schema is rejected locally;
- valid schema payload construction is valid JSON;
- aliases (`list`, `remove`, help/version flags) still resolve correctly;
- no production command requires a Docker socket;
- Compose files contain no fixed `container_name` after cleanup.

Use small fixture/stub scripts where needed rather than pulling Ollama/model weights into every PR check.

## 21.3 Add a Dockerfile/BuildKit structural gate

PR CI should perform a cheap Dockerfile/build-definition validation before the expensive release build.

The gate should catch:

- missing copied CLI paths;
- syntax/build-definition errors;
- accidental extra exposed ports;
- broken variant build arguments;
- accidental loss of healthcheck or expected entrypoint contract.

Avoid requiring the full 3B model download for this lightweight gate.

---

# 22. Release workflow safety and recovery

## 22.1 Add a safe manual recovery path

Add `workflow_dispatch` to the publication workflow so a failed scheduled/moving-tag refresh can be retried deliberately.

The manual path must be conservative:

- default to rebuilding/verifying moving tags from a selected stable release source;
- require an explicit input/condition before attempting an immutable release tag;
- run the same immutable-tag guard as release publication;
- never make a manual rerun a bypass around release safety checks.

## 22.2 Make scheduled source selection explicitly stable

The weekly refresh should resolve the latest **published stable** release intentionally.

Do not rely on a generic release-list ordering that could later select a prerelease if prereleases are introduced.

Add a regression check or explicit filtering logic for this contract.

## 22.3 Define prerelease tag behavior before one exists

If GitHub prereleases are used later:

- a prerelease may publish its explicit immutable prerelease tag only when deliberately supported;
- it must not move the stable `latest` / `amd-latest` tags unless the workflow explicitly opts into that policy;
- scheduled refresh continues from the latest stable published release.

## 22.4 Verify the pushed digest, not only the workflow exit code

After push:

- verify Docker Hub and GHCR resolve the expected tag/digest;
- verify standard/ROCm manifests expose only expected platforms;
- smoke-test a published candidate by digest where practical before considering publication complete;
- keep provenance/attestation attached to the actual digest;
- add SBOM attestation/publication where practical without blocking the core runtime on tooling fragility.

## 22.5 Keep current action majors current

The workflow already uses the current major lines for the main checkout/Docker/attestation actions at plan-review time.

Preserve the policy:

- use the newest compatible major versions;
- never downgrade merely for consistency with older LocalDevStack repositories;
- treat action-major updates as normal maintenance with CI validation.

---

# 23. Security and operational QoL additions

## 23.1 Keep CORS explicit

Do not enable broad browser access by default.

If a concrete browser client needs direct Ollama access:

- use explicit `OLLAMA_ORIGINS` values;
- prefer the LocalDevStack Nginx route and its policy controls;
- never use `*` merely to make development convenient without reviewing the exposure.

## 23.2 Keep authentication outside this provider image

The local Ollama API itself is not where this project should invent an authentication layer.

For LocalDevStack:

- bind standalone examples to localhost;
- use the internal Docker network for service-to-service traffic;
- let Nginx/LocalDevStack own any user-facing exposure policy;
- never publish `11434` broadly by default.

## 23.3 Prefer read-only repository mounts

Documentation should recommend read-only workspace mounts for analysis-only commands:

```text
review
code inspection
prompt/file context
```

Use writable mounts only for commands that intentionally mutate the repository, such as `ai-commit --yes` / `--edit`.

## 23.4 Keep operational logs in the orchestrator

After lifecycle command removal, document the canonical observability path:

```bash
docker compose ps
docker compose logs -f llm-sm
docker compose exec llm-sm llm-sm version
```

The provider CLI should expose model/API functionality; container state/log ownership remains outside it.

---

# 24. Extended acceptance gates

In addition to Section 15, the repository-wide hardening is complete when:

1. no Compose example hard-codes `container_name`;
2. multiple Compose projects can run concurrently when host ports/volume names are intentionally separated;
3. the stable Docker DNS service name remains `llm-sm`;
4. all model-aware CLI commands honor the same explicit/env/fallback precedence;
5. `json` no longer silently ignores the configured default model inside the image;
6. request JSON/schema handling is validated and no fragile hand-built payload path remains where `jq` should be used;
7. large prompt/file/diff input has an explicit, documented guard and is never silently truncated;
8. lifecycle modules and Docker-host lifecycle helpers are absent from the final production command surface;
9. CLI version CI assertions come from one authoritative source;
10. standard multi-arch publication is advertised only for architectures that pass the full model/runtime gate;
11. ROCm remains a separate `amd-*` family and advertises only validated platforms;
12. weekly refresh selects the latest stable published release explicitly;
13. manual publication recovery cannot bypass immutable-tag protection;
14. both registries are verified after push against the expected digest/manifest;
15. moving upstream Ollama base/version/model metadata is recorded for each publication;
16. daemon health remains independent from user-persistent model contents;
17. README examples clearly separate standalone `docker run` naming from Compose service execution;
18. LocalDevStack continues to work with `llm-sm` absent and never requires host port `11434` for internal AI traffic.

---

# 25. Additive implementation sequence

Do not replace the Section 16 order. Fold these review additions into it as follows:

1. During lifecycle cleanup, centralize model resolution and remove the production dependency on Docker-host helpers.
2. During lightweight CI expansion, add command/help/version/model-precedence/schema/Compose regression checks.
3. During Compose reconciliation, remove fixed `container_name`, switch Compose docs to `docker compose exec`, and document shared-vs-isolated volume behavior.
4. During runtime smoke work, separately validate daemon health, fresh-volume baked-model presence, missing-model behavior, streaming and persistence.
5. During Docker/publication hardening, add upstream-base identity recording, stable-release selection, manual recovery, immutable-tag protection and post-push digest verification.
6. Add standard `linux/arm64` publication only after a real native runtime/model smoke path exists; keep ROCm separate and architecture-limited to what is actually validated.
7. Add input-budget protection and benchmark the bundled `ai-commit` prompt before final documentation/release cleanup.
8. Re-run the full original LocalDevStack compatibility gate unchanged before publishing the next provider release.

---

# 26. Implementation tracker

Last updated: **2026-09-17**

Overall status: **repository implementation complete; release compatibility gate pending**

| Batch | Scope | Status |
|---|---|---|
| Batch 1 | CLI/runtime responsibility cleanup, model resolution, JSON/schema hardening, lightweight CLI regression gates | ✅ Complete |
| Batch 2 | Compose QoL, Dockerfile/runtime hardening, daemon/model/persistence smoke coverage | ✅ Complete |
| Batch 3 | Publication/release safety, stable-source resolution, digest verification, platform strategy | ✅ Complete |
| Batch 4 | README/QoL, Compose workspace mounting, input guards, provider-side interoperability, final sweep | ✅ Repo complete / 🚧 external release gate |

## Batch 1 — complete

Implementation commit: `5d3ff793e59d5867d4164a72f2be61c3a1a8e470`

- [x] Remove `start`, `stop`, `restart`, `status` and `logs` lifecycle commands.
- [x] Remove `scripts/lib/docker.sh` and bundled CLI Docker-host lifecycle dependency.
- [x] Keep the production CLI image-native and fail clearly when the Ollama runtime is unavailable.
- [x] Centralize model precedence as explicit option -> `LLM_SM_MODEL` -> `OLLAMA_MODEL` -> `qwen2.5:3b`.
- [x] Apply common model resolution to developer/model-aware commands.
- [x] Prevent `ollama run` from implicitly pulling a missing model; direct users to `llm-sm pull`.
- [x] Replace manual generate-payload JSON construction with `jq`.
- [x] Validate/compact JSON schema locally before API submission.
- [x] Add a bounded API connect timeout without imposing a total inference timeout.
- [x] Remove duplicated hard-coded CI version expectations and derive the expected CLI version from its source.
- [x] Add command-registry/help, lifecycle-removal, model-precedence, JSON-payload and malformed-schema regression gates.
- [x] Preserve Compose syntax/config validation in lightweight CI.

## Batch 2 — complete

Implementation commit: `687daea5f3dfbd977ba65538929c32e1231e10ca`

- [x] Remove fixed `container_name` from standalone/CPU/NVIDIA/AMD Compose definitions while preserving service key `llm-sm`.
- [x] Keep the shared `llm-sm-data` volume contract and add CI coverage for the `LLM_SM_VOLUME` isolation override.
- [x] Add explicit upstream runtime/package-manager preflight assumptions to the Dockerfile.
- [x] Change build readiness/model verification to validate the Ollama HTTP API as well as `ollama show`.
- [x] Keep daemon health independent from persistent model contents by probing `/api/tags` rather than the bundled CLI/default model.
- [x] Add explicit `STOPSIGNAL SIGTERM`.
- [x] Add a lightweight BuildKit/Dockerfile structural PR gate without executing the expensive model-bake layers.
- [x] Add reusable/manual `Runtime Check` workflow for the real standard-image bake and smoke path.
- [x] Add fresh-volume baked-model verification and API readiness coverage.
- [x] Add non-streaming generate plus streaming chat coverage and a bundled CLI inference request.
- [x] Add explicit missing-model failure validation without implicitly pulling another model.
- [x] Add persistent-volume recreation validation using the same baked model store, with no second large model download.
- [x] Add bounded health waiting, clean `docker stop`/SIGTERM checks and OOM-state checks.
- [x] Keep the expensive runtime workflow out of mandatory every-PR execution; Batch 3 wires the same smoke contract into release safety.

## Batch 3 — complete

Primary publication hardening commit: `c64307646f58fcaa0fcc026c0e84417f7842123e`

- [x] Add conservative `workflow_dispatch` recovery with optional source tag and explicit immutable-tag opt-in.
- [x] Resolve scheduled/manual default source through GitHub's latest published stable release endpoint.
- [x] Prevent prereleases from moving stable `latest` / `amd-latest` tags.
- [x] Add immutable-tag existence guards for Docker Hub and GHCR.
- [x] Add publication concurrency and 120-minute job bounds.
- [x] Resolve `ollama/ollama:latest` / `ollama/ollama:rocm` once to a digest per variant so validation and publication use identical upstream bits.
- [x] Build an explicit `linux/amd64` candidate for each variant before publication.
- [x] Run the current Batch 2 runtime harness against the standard release candidate while allowing older stable source tags to be validated with current tooling.
- [x] Record upstream base digest, Ollama version, bundled CLI version, model metadata and published digest.
- [x] Enable BuildKit provenance and SBOM plus Docker Hub/GHCR attestations.
- [x] Verify Docker Hub and GHCR resolve the pushed digest and can pull it as `linux/amd64`.
- [x] Re-check the published standard image by digest before publication is considered complete.
- [x] Keep standard and ROCm publication families separate.
- [x] Keep arm64 disabled until a real native model/runtime gate exists; CI rejects accidental multi-arch enablement.

## Batch 4 — repository implementation complete

Implementation range: `354b2257c5a3513fea6909f9dbc938208269dfc5` through `dca09d4c67d192bca230584251d762aa70d13d29`

Notable provider-contract test: `b5d85d60b0caf0b70a6965c5fa885d6a6b32b03b`

Prompt benchmark harness: `32a41cb81720605b00305b79d14a8f921414c67c`

- [x] Add `compose.workspace.yml` as an optional repository/workspace bind-mount override.
- [x] Mount workspaces at `/workspace` without changing the persistent `/root/.ollama` model volume.
- [x] Default workspace mounts to read-only and require deliberate `LLM_SM_WORKSPACE_MODE=rw` for mutating Git operations.
- [x] Add CI coverage proving workspace overlay + model volume coexist and read-only/read-write behavior is explicit.
- [x] Add byte-based soft/hard context guards to `prompt`, `code`, `review` and `ai-commit`.
- [x] Never silently truncate oversized context; allow only explicit `LLM_SM_ALLOW_LARGE_INPUT=1` bypass.
- [x] Document workspace mounting, model-store sharing/isolation, input guards, provider boundaries, LocalDevStack URLs and release safety in the README.
- [x] Add a peer-container runtime smoke proving `http://llm-sm:11434` works through Docker DNS with no host port mapping.
- [x] Add OpenAI-compatible `/v1/chat/completions` runtime validation.
- [x] Confirm the Nginx hardening branch contains complementary `llm.localhost` route, streaming, missing-provider and late-start DNS smoke coverage.
- [x] Add an `ai-commit` prompt benchmark harness so prompt size/latency can be compared without weakening output rules blindly.
- [x] Keep the existing bundled commit prompt unchanged until an empirical candidate benchmark demonstrates no quality regression.

## Release compatibility gate — still required

Do **not** publish the next provider release yet solely because repository implementation is complete.

The following external/runtime checks remain intentionally open:

- [ ] Run the lightweight CLI/Compose/Dockerfile CI on the completed branch/PR.
- [ ] Run the model-bearing `Runtime Check` workflow on the completed standard image path.
- [ ] Integrate `llm-sm` as an optional service in LocalDevStack and prove stack startup with and without it.
- [ ] Integrate docker-tools' provider abstraction with `http://llm-sm:11434` and prove graceful behavior when the provider is absent.
- [ ] Run the full Nginx + real `llm-sm` end-to-end route test for `https://llm.localhost`, including streaming `/api/chat`, `/api/generate` and `/v1/...`.
- [ ] Run the prompt benchmark harness against any proposed reduced prompt before changing the bundled prompt.
- [ ] Perform real ROCm runtime validation only on suitable AMD hardware; CPU CI must not be treated as a ROCm runtime proof.
- [ ] Add standard arm64 publication only after a native arm64 build/model/runtime gate exists.

Current dependency observation at this tracker update:

- `docker-nginx` hardening already contains dedicated `llm.localhost` route/streaming contract tests.
- LocalDevStack `main` does not yet expose an `llm-sm` service contract.
- docker-tools `main` does not yet expose an `llm-sm` provider contract.

Therefore the provider repository itself is ready for PR/final CI, while Section 14 remains the deliberate release blocker until the downstream stack integration is completed.

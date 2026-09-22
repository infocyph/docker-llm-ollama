ARG OLLAMA_BASE_IMAGE=ollama/ollama:latest
FROM ${OLLAMA_BASE_IMAGE}

ARG LLM_OLLAMA_VERSION

LABEL org.opencontainers.image.source="https://github.com/infocyph/docker-llm-ollama"
LABEL org.opencontainers.image.description="Local small LLM runtime powered by Ollama"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.authors="infocyph,abmmhasan"
LABEL org.opencontainers.image.version="${LLM_OLLAMA_VERSION}"

ARG OLLAMA_MODEL=qwen3.5:9b

ENV LLM_OLLAMA_VERSION=${LLM_OLLAMA_VERSION} \
    OLLAMA_HOST=0.0.0.0:11434 \
    OLLAMA_NUM_PARALLEL=1 \
    OLLAMA_MAX_LOADED_MODELS=1 \
    OLLAMA_KEEP_ALIVE=5m \
    OLLAMA_NO_CLOUD=1 \
    OLLAMA_MODEL=${OLLAMA_MODEL} \
    LLM_OLLAMA_IN_CONTAINER=1 \
    LLM_OLLAMA_URL=http://127.0.0.1:11434

RUN set -eu; \
    test -x /bin/ollama; \
    /bin/ollama --version; \
    command -v apt-get >/dev/null 2>&1

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl git jq poppler-utils \
    && command -v pdftotext >/dev/null \
    && command -v pdftoppm >/dev/null \
    && command -v pdfinfo >/dev/null \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/llm-ollama /usr/local/bin/llm-ollama
COPY scripts/lib /usr/local/lib/llm-ollama/lib
COPY scripts/commands /usr/local/lib/llm-ollama/commands
COPY scripts/prompts /usr/local/lib/llm-ollama/prompts

RUN chmod 0755 /usr/local/bin/llm-ollama \
    && chmod -R a+rX /usr/local/lib/llm-ollama

# Bake the default model into the image so the container is immediately usable
# without downloading model weights on first startup.
RUN set -eu; \
    export OLLAMA_HOST=127.0.0.1:11434; \
    export OLLAMA_NO_CLOUD=0; \
    /bin/ollama serve >/tmp/ollama-build.log 2>&1 & \
    pid=$!; \
    cleanup() { \
        kill "$pid" >/dev/null 2>&1 || true; \
        wait "$pid" 2>/dev/null || true; \
    }; \
    trap cleanup EXIT INT TERM; \
    attempts=0; \
    until curl --connect-timeout 1 -fsS http://127.0.0.1:11434/api/tags >/tmp/ollama-tags.json 2>/dev/null; do \
        attempts=$((attempts + 1)); \
        if [ "$attempts" -ge 60 ]; then \
            cat /tmp/ollama-build.log; \
            exit 1; \
        fi; \
        sleep 1; \
    done; \
    /bin/ollama pull "$OLLAMA_MODEL"; \
    /bin/ollama show "$OLLAMA_MODEL" >/dev/null; \
    curl --connect-timeout 3 -fsS http://127.0.0.1:11434/api/tags >/tmp/ollama-tags.json; \
    jq -e --arg model "$OLLAMA_MODEL" 'any(.models[]?; .name == $model or .model == $model)' /tmp/ollama-tags.json >/dev/null; \
    rm -f /tmp/ollama-build.log /tmp/ollama-tags.json

EXPOSE 11434

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD curl --connect-timeout 2 -fsS http://127.0.0.1:11434/api/tags >/dev/null || exit 1

STOPSIGNAL SIGTERM

ENTRYPOINT ["/bin/ollama"]
CMD ["serve"]

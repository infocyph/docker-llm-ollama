#!/usr/bin/env bash

container_exists() {
  docker inspect "$CONTAINER" >/dev/null 2>&1
}

container_running() {
  [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)" == "true" ]]
}

require_container() {
  container_exists || die "Container '$CONTAINER' does not exist. Start it with Docker Compose or docker run first."
}

require_running() {
  require_container
  container_running || die "Container '$CONTAINER' is not running. Run: llm-sm start"
}

container_model() {
  local model
  model="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER" 2>/dev/null \
    | sed -n 's/^OLLAMA_MODEL=//p' \
    | head -n 1 || true)"

  printf '%s\n' "${model:-$DEFAULT_MODEL_FALLBACK}"
}

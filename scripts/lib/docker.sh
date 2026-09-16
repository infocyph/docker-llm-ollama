#!/usr/bin/env bash

in_container() {
  [[ "${LLM_SM_IN_CONTAINER:-0}" == "1" ]]
}

container_exists() {
  if in_container; then
    return 0
  fi
  docker inspect "$CONTAINER" >/dev/null 2>&1
}

container_running() {
  if in_container; then
    return 0
  fi
  [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)" == "true" ]]
}

require_container() {
  container_exists || die "Container '$CONTAINER' does not exist. Start it with Docker Compose or docker run first."
}

require_running() {
  require_container
  container_running || die "Container '$CONTAINER' is not running."
}

container_model() {
  if in_container; then
    printf '%s\n' "${LLM_SM_MODEL:-${OLLAMA_MODEL:-$DEFAULT_MODEL_FALLBACK}}"
    return 0
  fi

  local model
  model="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER" 2>/dev/null \
    | sed -n 's/^OLLAMA_MODEL=//p' \
    | head -n 1 || true)"

  printf '%s\n' "${model:-$DEFAULT_MODEL_FALLBACK}"
}

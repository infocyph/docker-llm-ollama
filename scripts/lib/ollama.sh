#!/usr/bin/env bash

ollama_runtime() {
  printf '%s\n' "/bin/ollama"
}

require_ollama_runtime() {
  local bin
  bin="$(ollama_runtime)"
  [[ -x "$bin" ]] || die "Ollama runtime is unavailable. Run llm-sm inside the published llm-sm container."
}

exec_ollama() {
  local bin
  require_ollama_runtime
  bin="$(ollama_runtime)"
  OLLAMA_HOST=127.0.0.1:11434 "$bin" "$@"
}

model_available() {
  local model="$1" bin
  bin="$(ollama_runtime)"
  [[ -x "$bin" ]] || return 1
  OLLAMA_HOST=127.0.0.1:11434 "$bin" show "$model" >/dev/null 2>&1
}

require_model() {
  local model="$1"
  require_ollama_runtime
  model_available "$model" || die "Model '$model' is not installed. Run 'llm-sm pull $model' first."
}

api_url() {
  local path="${1:-/}"

  case "$path" in
    http://*|https://*) printf '%s\n' "$path" ;;
    /*) printf '%s%s\n' "${API_URL%/}" "$path" ;;
    *) printf '%s/%s\n' "${API_URL%/}" "$path" ;;
  esac
}

run_text_prompt() {
  local model="$1"
  local instruction="$2"
  local content="$3"
  local prompt

  require_model "$model"

  if [[ -n "$instruction" ]]; then
    prompt="$instruction

$content"
  else
    prompt="$content"
  fi

  exec_ollama run "$model" "$prompt"
}

build_generate_payload() {
  require_command jq

  local model="$1"
  local prompt="$2"
  local format_json="$3"

  jq -cn \
    --arg model "$model" \
    --arg prompt "$prompt" \
    --argjson format "$format_json" \
    '{model: $model, prompt: $prompt, stream: false, format: $format}'
}

post_generate_json() {
  require_command curl

  local model="$1"
  local prompt="$2"
  local format_json="$3"
  local body

  body="$(build_generate_payload "$model" "$prompt" "$format_json")"

  curl --connect-timeout 3 --fail-with-body -sS \
    -H 'Content-Type: application/json' \
    -d "$body" \
    "$(api_url /api/generate)"
}

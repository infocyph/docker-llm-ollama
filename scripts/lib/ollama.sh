#!/usr/bin/env bash

exec_ollama() {
  require_command docker
  require_running

  local exec_args=(-i)
  if [[ -t 0 && -t 1 ]]; then
    exec_args=(-it)
  fi

  docker exec "${exec_args[@]}" "$CONTAINER" /bin/ollama "$@"
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

  if [[ -n "$instruction" ]]; then
    prompt="$instruction

$content"
  else
    prompt="$content"
  fi

  exec_ollama run "$model" "$prompt"
}

post_generate_json() {
  require_command curl

  local model="$1"
  local prompt="$2"
  local format_json="$3"
  local model_json prompt_json body

  model_json="$(json_quote "$model")"
  prompt_json="$(json_quote "$prompt")"
  body="{\"model\":${model_json},\"prompt\":${prompt_json},\"stream\":false,\"format\":${format_json}}"

  curl --fail-with-body -sS \
    -H 'Content-Type: application/json' \
    -d "$body" \
    "$(api_url /api/generate)"
}

#!/usr/bin/env bash

ollama_runtime() {
  printf '%s\n' "/bin/ollama"
}

require_ollama_runtime() {
  local bin
  bin="$(ollama_runtime)"
  [[ -x "$bin" ]] || die "Ollama runtime is unavailable. Run llm-ollama inside the published llm-ollama container."
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
  model_available "$model" || die "Model '$model' is not installed. Run 'llm-ollama pull $model' first."
}

api_url() {
  local path="${1:-/}"

  case "$path" in
    http://*|https://*) printf '%s\n' "$path" ;;
    /*) printf '%s%s\n' "${API_URL%/}" "$path" ;;
    *) printf '%s/%s\n' "${API_URL%/}" "$path" ;;
  esac
}

model_info_json() {
  require_command curl
  require_command jq

  local model="$1"
  local payload
  payload="$(jq -cn --arg model "$model" '{model:$model}')"

  curl --connect-timeout 3 --fail-with-body -sS \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    "$(api_url /api/show)"
}

require_model_capability() {
  local model="$1"
  local capability="$2"
  local info

  info="$(model_info_json "$model")" || die "Unable to inspect capabilities for model '$model'"

  if ! jq -e --arg capability "$capability" '(.capabilities // []) | index($capability) != null' <<<"$info" >/dev/null; then
    if [[ "$capability" == "vision" ]]; then
      die "Model '$model' does not expose vision capability. Select or pull a vision model, for example: llm-ollama pull qwen2.5vl:3b"
    fi
    die "Model '$model' does not expose required capability '$capability'"
  fi
}

encode_images_json() {
  require_command jq
  require_command base64

  local output_file="$1"
  shift
  local image
  local encoded_file
  check_attachment_bytes_set "Vision payload" "$@"
  encoded_file="$(mktemp)"

  for image in "$@"; do
    [[ -f "$image" ]] || {
      rm -f -- "$encoded_file"
      die "Image file not found: $image"
    }
    [[ -s "$image" ]] || {
      rm -f -- "$encoded_file"
      die "Image file is empty: $image"
    }
    base64 "$image" | tr -d '\r\n' >> "$encoded_file"
    printf '\n' >> "$encoded_file"
  done

  jq -Rsc 'split("\n") | map(select(length > 0))' "$encoded_file" > "$output_file"
  rm -f -- "$encoded_file"
}

normalize_think_mode() {
  case "${1:-}" in
    "") printf '%s' "" ;;
    1|true|TRUE|yes|YES|on|ON) printf '%s' true ;;
    0|false|FALSE|no|NO|off|OFF) printf '%s' false ;;
    *) die "LLM_OLLAMA_THINK must be true/false when set" ;;
  esac
}

build_chat_payload() {
  require_command jq

  local model="$1"
  local system_file="$2"
  local content_file="$3"
  local images_file="$4"
  local output_file="$5"
  local think

  think="$(normalize_think_mode "${LLM_OLLAMA_THINK:-}")"

  jq -n \
    --arg model "$model" \
    --rawfile system "$system_file" \
    --rawfile content "$content_file" \
    --slurpfile images "$images_file" \
    --arg think "$think" \
    '{
      model: $model,
      messages:
        ((if ($system | length) > 0 then [{role:"system", content:$system}] else [] end)
        + [{
            role:"user",
            content:$content
          }]),
      stream: false
    }
    | if (($images[0] // []) | length) > 0
      then .messages[-1].images = $images[0]
      else .
      end
    | if $think == "" then .
      else . + {think: ($think == "true")}
      end' > "$output_file"
}

run_chat_prompt() {
  local model="$1"
  local instruction="$2"
  local content="$3"
  shift 3
  local -a images=("$@")
  local tmp_dir system_file content_file images_file payload_file response_file response

  require_model "$model"
  require_command curl
  require_command jq

  if (( ${#images[@]} > 0 )); then
    require_model_capability "$model" vision
  fi

  tmp_dir="$(mktemp -d)"
  system_file="$tmp_dir/system.txt"
  content_file="$tmp_dir/content.txt"
  images_file="$tmp_dir/images.json"
  payload_file="$tmp_dir/request.json"
  response_file="$tmp_dir/response.json"

  printf '%s' "$instruction" > "$system_file"
  printf '%s' "$content" > "$content_file"
  encode_images_json "$images_file" "${images[@]}"
  build_chat_payload "$model" "$system_file" "$content_file" "$images_file" "$payload_file"

  if ! curl --connect-timeout 3 --fail-with-body -sS \
      -H 'Content-Type: application/json' \
      -d @"$payload_file" \
      "$(api_url /api/chat)" > "$response_file"; then
    [[ ! -s "$response_file" ]] || cat "$response_file" >&2
    rm -rf -- "$tmp_dir"
    die "Ollama failed to process the request"
  fi

  response="$(jq -er '.message.content // empty' "$response_file")" || {
    cat "$response_file" >&2
    rm -rf -- "$tmp_dir"
    die "Ollama response did not contain message content"
  }

  rm -rf -- "$tmp_dir"
  printf '%s\n' "$response"
}

run_text_prompt() {
  local model="$1"
  local instruction="$2"
  local content="$3"

  run_chat_prompt "$model" "$instruction" "$content"
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
    '{model: $model, prompt: $prompt, stream: false, format: $format, think: false}'
}

post_generate_json() {
  require_command curl
  require_command jq

  local model="$1"
  local prompt="$2"
  local format_json="$3"
  local tmp_dir prompt_file format_file payload_file response_file

  require_model "$model"

  tmp_dir="$(mktemp -d)"
  prompt_file="$tmp_dir/prompt.txt"
  format_file="$tmp_dir/format.json"
  payload_file="$tmp_dir/request.json"
  response_file="$tmp_dir/response.json"

  printf '%s' "$prompt" > "$prompt_file"
  printf '%s\n' "$format_json" > "$format_file"

  jq -n \
    --arg model "$model" \
    --rawfile prompt "$prompt_file" \
    --slurpfile format "$format_file" \
    '{model:$model, prompt:$prompt, stream:false, format:$format[0], think:false}' > "$payload_file"

  if ! curl --connect-timeout 3 --fail-with-body -sS \
      -H 'Content-Type: application/json' \
      -d @"$payload_file" \
      "$(api_url /api/generate)" > "$response_file"; then
    [[ ! -s "$response_file" ]] || cat "$response_file" >&2
    rm -rf -- "$tmp_dir"
    die "Ollama failed to generate structured output"
  fi

  cat "$response_file"
  rm -rf -- "$tmp_dir"
}

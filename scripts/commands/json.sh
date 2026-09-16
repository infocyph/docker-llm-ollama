#!/usr/bin/env bash

command_main() {
  local model schema_file response_only prompt format_json response
  model="${LLM_SM_MODEL:-$DEFAULT_MODEL_FALLBACK}"
  schema_file=""
  response_only=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--model)
        [[ $# -ge 2 ]] || die "Missing model after $1"
        model="$2"
        shift 2
        ;;
      --schema)
        [[ $# -ge 2 ]] || die "Missing schema file after $1"
        schema_file="$2"
        shift 2
        ;;
      -r|--response-only)
        response_only=1
        shift
        ;;
      --)
        shift
        break
        ;;
      -*) die "Unknown option: $1" ;;
      *) break ;;
    esac
  done

  prompt="$(read_input "$@")" || die "Prompt required. Example: llm-sm json \"Return name and version\""
  [[ -n "$prompt" ]] || die "Prompt cannot be empty"

  if [[ -n "$schema_file" ]]; then
    [[ -f "$schema_file" ]] || die "Schema file not found: $schema_file"
    format_json="$(cat -- "$schema_file")"
    [[ -n "$format_json" ]] || die "Schema file is empty: $schema_file"
  else
    format_json='"json"'
  fi

  response="$(post_generate_json "$model" "$prompt" "$format_json")"

  if (( response_only )); then
    require_command jq
    printf '%s\n' "$response" | jq -er '.response' | jq .
  else
    printf '%s\n' "$response"
  fi
}

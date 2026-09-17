#!/usr/bin/env bash

command_main() {
  local model="" schema_file response_only prompt format_json response
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

  require_command jq
  model="$(resolve_model "$model")"
  prompt="$(read_input "$@")" || die "Prompt required. Example: llm-sm json \"Return name and version\""
  [[ -n "$prompt" ]] || die "Prompt cannot be empty"

  if [[ -n "$schema_file" ]]; then
    [[ -f "$schema_file" ]] || die "Schema file not found: $schema_file"
    [[ -s "$schema_file" ]] || die "Schema file is empty: $schema_file"
    format_json="$(jq -ce . "$schema_file" 2>/dev/null)" || die "Schema file is not valid JSON: $schema_file"
  else
    format_json='"json"'
  fi

  response="$(post_generate_json "$model" "$prompt" "$format_json")"

  if (( response_only )); then
    printf '%s\n' "$response" | jq -er '.response' | jq .
  else
    printf '%s\n' "$response"
  fi
}

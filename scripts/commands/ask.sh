#!/usr/bin/env bash

command_main() {
  local model prompt
  model="$(container_model)"

  if [[ "${1:-}" == "-m" || "${1:-}" == "--model" ]]; then
    [[ $# -ge 2 ]] || die "Missing model after $1"
    model="$2"
    shift 2
  fi

  prompt="$(read_input "$@")" || die "Prompt required. Example: llm-sm ask \"Hello\""
  [[ -n "$prompt" ]] || die "Prompt cannot be empty"

  exec_ollama run "$model" "$prompt"
}

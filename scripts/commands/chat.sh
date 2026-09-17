#!/usr/bin/env bash

command_main() {
  local model=""

  if [[ "${1:-}" == "-m" || "${1:-}" == "--model" ]]; then
    [[ $# -ge 2 ]] || die "Missing model after $1"
    model="$2"
    shift 2
  elif [[ $# -gt 0 ]]; then
    model="$1"
    shift
  fi

  [[ $# -eq 0 ]] || die "Usage: llm-sm chat [model]"
  model="$(resolve_model "$model")"
  require_model "$model"
  exec_ollama run "$model"
}

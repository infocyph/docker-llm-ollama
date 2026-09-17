#!/usr/bin/env bash

command_main() {
  local model
  [[ $# -ge 1 ]] || die "Model required. Example: llm-sm run qwen2.5:3b"
  model="$1"
  shift
  require_model "$model"
  exec_ollama run "$model" "$@"
}

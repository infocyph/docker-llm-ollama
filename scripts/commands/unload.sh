#!/usr/bin/env bash

command_main() {
  local model
  [[ $# -le 1 ]] || die "Usage: llm-sm unload [model]"
  model="$(resolve_model "${1:-}")"
  exec_ollama stop "$model"
}

#!/usr/bin/env bash

command_main() {
  local model
  model="${1:-$(container_model)}"
  [[ $# -le 1 ]] || die "Usage: llm-sm show [model]"
  exec_ollama show "$model"
}

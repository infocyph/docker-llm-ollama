#!/usr/bin/env bash

command_main() {
  [[ $# -ge 1 ]] || die "Model required. Example: llm-sm run qwen2.5:3b"
  exec_ollama run "$@"
}

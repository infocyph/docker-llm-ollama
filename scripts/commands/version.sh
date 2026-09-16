#!/usr/bin/env bash

command_main() {
  [[ $# -eq 0 ]] || die "Usage: llm-sm version"

  printf 'llm-sm %s\n' "$VERSION"

  if in_container; then
    OLLAMA_HOST=127.0.0.1:11434 /bin/ollama --version
  elif command -v docker >/dev/null 2>&1 && container_running; then
    exec_ollama --version
  fi
}

#!/usr/bin/env bash

command_main() {
  [[ $# -eq 0 ]] || die "Usage: llm-ollama version"

  printf 'llm-ollama %s\n' "$VERSION"

  if [[ -x /bin/ollama ]]; then
    OLLAMA_HOST=127.0.0.1:11434 /bin/ollama --version
  fi
}

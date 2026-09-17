#!/usr/bin/env bash

command_main() {
  [[ $# -eq 0 ]] || die "Usage: llm-sm version"

  printf 'llm-sm %s\n' "$VERSION"

  if [[ -x /bin/ollama ]]; then
    OLLAMA_HOST=127.0.0.1:11434 /bin/ollama --version
  fi
}

#!/usr/bin/env bash

command_main() {
  [[ $# -eq 1 ]] || die "Usage: llm-ollama pull <model>"
  exec_ollama pull "$1"
}

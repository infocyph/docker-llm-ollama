#!/usr/bin/env bash

command_main() {
  [[ $# -eq 1 ]] || die "Usage: llm-ollama rm <model>"
  exec_ollama rm "$1"
}

#!/usr/bin/env bash

command_main() {
  [[ $# -ge 1 ]] || die "Ollama arguments required"
  exec_ollama "$@"
}

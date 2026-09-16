#!/usr/bin/env bash

command_main() {
  [[ $# -eq 0 ]] || die "Usage: llm-sm ps"
  exec_ollama ps
}

#!/usr/bin/env bash

command_main() {
  require_command docker
  require_container

  if [[ $# -eq 0 ]]; then
    docker logs -f "$CONTAINER"
  else
    docker logs "$@" "$CONTAINER"
  fi
}

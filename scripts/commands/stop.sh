#!/usr/bin/env bash

command_main() {
  require_command docker
  require_container
  docker stop "$CONTAINER"
}

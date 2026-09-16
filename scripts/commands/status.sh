#!/usr/bin/env bash

command_main() {
  require_command docker

  if ! container_exists; then
    printf 'Container: %snot found%s (%s)\n' "$RED" "$RESET" "$CONTAINER"
    printf 'API:       %s\n' "$API_URL"
    return 1
  fi

  local state health model
  state="$(docker inspect -f '{{.State.Status}}' "$CONTAINER")"
  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}not-configured{{end}}' "$CONTAINER")"
  model="$(container_model)"

  printf 'Container: %s (%s)\n' "$CONTAINER" "$state"
  printf 'Health:    %s\n' "$health"
  printf 'API:       %s\n' "$API_URL"
  printf 'Model:     %s\n' "$model"

  if container_running; then
    if command -v curl >/dev/null 2>&1 && curl -fsS --max-time 2 "$(api_url /api/tags)" >/dev/null 2>&1; then
      printf 'API state: %sreachable%s\n' "$GREEN" "$RESET"
    else
      printf 'API state: %sunreachable%s\n' "$YELLOW" "$RESET"
    fi
  fi
}

#!/usr/bin/env bash

# Shared by dynamically loaded command modules.
# shellcheck disable=SC2034
VERSION="0.4.0"
CONTAINER="${LLM_SM_CONTAINER:-llm-sm}"
API_URL="${LLM_SM_URL:-http://127.0.0.1:${OLLAMA_PORT:-11434}}"
DEFAULT_MODEL_FALLBACK="${LLM_SM_MODEL:-qwen2.5:3b}"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  RED=$'\033[31m'
  RESET=$'\033[0m'
else
  BOLD=''
  GREEN=''
  YELLOW=''
  RED=''
  RESET=''
fi

info() { printf '%s\n' "${GREEN}$*${RESET}"; }
warn() { printf '%s\n' "${YELLOW}$*${RESET}" >&2; }
die() { printf '%s\n' "${RED}Error:${RESET} $*" >&2; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

read_input() {
  if [[ $# -gt 0 ]]; then
    printf '%s\n' "$*"
  elif [[ ! -t 0 ]]; then
    cat
  else
    return 1
  fi
}

read_stdin_if_piped() {
  if [[ ! -t 0 ]]; then
    cat
  fi
}

file_context() {
  local file first=1

  for file in "$@"; do
    [[ -f "$file" ]] || die "File not found: $file"

    if (( ! first )); then
      printf '\n\n'
    fi
    first=0

    printf '%s\n' "--- FILE: $file ---"
    cat -- "$file"
  done
}

json_quote() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\b'/\\b}
  value=${value//$'\f'/\\f}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '"%s"' "$value"
}

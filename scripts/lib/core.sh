#!/usr/bin/env bash

# Shared by dynamically loaded command modules.
# shellcheck disable=SC2034
VERSION="0.4.0"
API_URL="${LLM_SM_URL:-http://127.0.0.1:11434}"
DEFAULT_MODEL_FALLBACK="qwen2.5:3b"
DEFAULT_INPUT_WARN_BYTES=1048576
DEFAULT_INPUT_MAX_BYTES=0

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

resolve_model() {
  local explicit="${1:-}"
  printf '%s\n' "${explicit:-${LLM_SM_MODEL:-${OLLAMA_MODEL:-$DEFAULT_MODEL_FALLBACK}}}"
}

validate_input_limits() {
  local warn_bytes="${LLM_SM_INPUT_WARN_BYTES:-$DEFAULT_INPUT_WARN_BYTES}"
  local max_bytes="${LLM_SM_INPUT_MAX_BYTES:-$DEFAULT_INPUT_MAX_BYTES}"

  [[ "$warn_bytes" =~ ^[0-9]+$ ]] || die "LLM_SM_INPUT_WARN_BYTES must be a non-negative integer"
  [[ "$max_bytes" =~ ^[0-9]+$ ]] || die "LLM_SM_INPUT_MAX_BYTES must be a non-negative integer"

  if (( max_bytes > 0 && warn_bytes > max_bytes )); then
    die "LLM_SM_INPUT_WARN_BYTES cannot exceed a non-zero LLM_SM_INPUT_MAX_BYTES"
  fi
}

check_input_bytes() {
  local label="$1"
  local bytes="$2"
  local warn_bytes="${LLM_SM_INPUT_WARN_BYTES:-$DEFAULT_INPUT_WARN_BYTES}"
  local max_bytes="${LLM_SM_INPUT_MAX_BYTES:-$DEFAULT_INPUT_MAX_BYTES}"

  validate_input_limits
  [[ "$bytes" =~ ^[0-9]+$ ]] || die "Invalid byte count for $label"

  if (( max_bytes > 0 && bytes > max_bytes )) && [[ "${LLM_SM_ALLOW_LARGE_INPUT:-0}" != "1" ]]; then
    die "$label is ${bytes} bytes; the configured safety limit is ${max_bytes}. Narrow the input, raise LLM_SM_INPUT_MAX_BYTES, set it to 0 for unlimited input, or set LLM_SM_ALLOW_LARGE_INPUT=1 deliberately."
  fi

  if (( warn_bytes > 0 && bytes > warn_bytes )); then
    warn "$label is ${bytes} bytes; the selected model may be slow or lose useful context. The request will still be sent."
  fi
}

check_input_budget() {
  local label="$1"
  local input="$2"
  local bytes
  bytes="$(LC_ALL=C printf '%s' "$input" | wc -c | tr -d '[:space:]')"
  check_input_bytes "$label" "$bytes"
}

check_file_budget() {
  local label="$1"
  local file="$2"
  [[ -f "$file" ]] || die "File not found: $file"
  local bytes
  bytes="$(LC_ALL=C wc -c < "$file" | tr -d '[:space:]')"
  check_input_bytes "$label" "$bytes"
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

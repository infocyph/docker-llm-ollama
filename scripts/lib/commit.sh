#!/usr/bin/env bash

ai_commit_source_url() {
  local source_file="$LLM_SM_RUNTIME_ROOT/prompts/ai-commit.source"
  [[ -f "$source_file" ]] || die "AI commit prompt source file not found: $source_file"

  sed -n '/^[[:space:]]*#/d; /^[[:space:]]*$/d; p; q' "$source_file"
}

extract_gitx_prompt_b64() {
  sed -n 's/^[[:space:]]*sys_instruction_b64="\([^"]*\)"[[:space:]]*$/\1/p' | head -n 1
}

decode_base64() {
  local encoded="$1"

  if printf '%s' "$encoded" | base64 --decode 2>/dev/null; then
    return 0
  fi

  printf '%s' "$encoded" | base64 -D 2>/dev/null
}

validate_ai_commit_prompt_b64() {
  local encoded="$1"
  local decoded

  [[ -n "$encoded" ]] || return 1
  decoded="$(decode_base64 "$encoded")" || return 1
  [[ "$decoded" == You\ are\ a\ commit\ message\ generator.* ]]
}

ai_commit_cache_file() {
  printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/llm-sm/ai-commit.b64"
}

load_ai_commit_prompt_b64() {
  local refresh="${1:-0}"
  local candidate=""
  local gitx_file=""
  local cache_file
  cache_file="$(ai_commit_cache_file)"

  if [[ -n "${LLM_SM_AI_COMMIT_PROMPT_B64:-}" ]]; then
    candidate="$LLM_SM_AI_COMMIT_PROMPT_B64"
    validate_ai_commit_prompt_b64 "$candidate" || die "LLM_SM_AI_COMMIT_PROMPT_B64 is invalid"
    printf '%s\n' "$candidate"
    return 0
  fi

  if [[ -n "${GITX_SYS_INSTRUCTION_B64:-}" ]]; then
    candidate="$GITX_SYS_INSTRUCTION_B64"
    validate_ai_commit_prompt_b64 "$candidate" || die "GITX_SYS_INSTRUCTION_B64 is invalid"
    printf '%s\n' "$candidate"
    return 0
  fi

  if [[ -f "$HOME/.config/gitx/instructions.b64" ]]; then
    candidate="$(tr -d '\r\n' < "$HOME/.config/gitx/instructions.b64")"
    if validate_ai_commit_prompt_b64 "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  gitx_file="$(command -v gitx 2>/dev/null || true)"
  if [[ -n "$gitx_file" && -f "$gitx_file" ]]; then
    candidate="$(extract_gitx_prompt_b64 < "$gitx_file")"
    if validate_ai_commit_prompt_b64 "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  if (( ! refresh )) && [[ -f "$cache_file" ]]; then
    candidate="$(tr -d '\r\n' < "$cache_file")"
    if validate_ai_commit_prompt_b64 "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  require_command curl
  local source_url
  source_url="$(ai_commit_source_url)"
  [[ -n "$source_url" ]] || die "AI commit prompt source URL is empty"

  candidate="$(curl -fsSL "$source_url" | extract_gitx_prompt_b64)" || \
    die "Unable to retrieve ai-commit prompt from Toolset"
  validate_ai_commit_prompt_b64 "$candidate" || \
    die "Toolset returned an invalid ai-commit prompt"

  mkdir -p -- "$(dirname -- "$cache_file")"
  printf '%s\n' "$candidate" > "$cache_file"
  chmod 0600 "$cache_file" 2>/dev/null || true

  printf '%s\n' "$candidate"
}

load_ai_commit_prompt() {
  local encoded
  encoded="$(load_ai_commit_prompt_b64 "${1:-0}")"
  decode_base64 "$encoded" || die "Unable to decode ai-commit prompt"
}

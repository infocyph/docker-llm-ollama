#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$LLM_SM_RUNTIME_ROOT/lib/commit.sh"

print_ai_commit_help() {
  cat <<'EOF'
Usage: llm-sm ai-commit [options]

Generate a commit message from staged changes using the same prompt as
infocyph/Toolset's `gitx ai-commit`, but run inference through local Ollama.

Options:
  -m, --model <model>   Override the Ollama model
  -y, --yes             Commit immediately with the generated message
  -e, --edit            Open the generated message in $EDITOR, then commit
  -p, --print           Print only the generated message; do not commit
      --refresh-prompt  Refresh the cached canonical Toolset prompt
  -h, --help            Show this help

Prompt precedence:
  1. LLM_SM_AI_COMMIT_PROMPT_B64
  2. GITX_SYS_INSTRUCTION_B64
  3. ~/.config/gitx/instructions.b64
  4. Prompt embedded in the installed `gitx`
  5. Cached Toolset prompt
  6. infocyph/Toolset main branch (then cached)
EOF
}

commit_with_message_file() {
  local commit_msg="$1"
  local edit="${2:-0}"
  local msg_file="$AI_COMMIT_TMP/commit-message.txt"

  printf '%s\n' "$commit_msg" > "$msg_file"

  if (( edit )); then
    local editor_value="${EDITOR:-vi}"
    local -a editor_cmd=()
    read -r -a editor_cmd <<< "$editor_value"
    [[ ${#editor_cmd[@]} -gt 0 ]] || editor_cmd=(vi)
    "${editor_cmd[@]}" "$msg_file"
  fi

  [[ -s "$msg_file" ]] || die "Commit message is empty"
  git commit -F "$msg_file"
  info "Committed successfully."
}

command_main() {
  local model="${LLM_SM_MODEL:-}"
  local action="interactive"
  local refresh_prompt=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--model)
        [[ $# -ge 2 ]] || die "Missing model after $1"
        model="$2"
        shift 2
        ;;
      -y|--yes)
        action="yes"
        shift
        ;;
      -e|--edit)
        action="edit"
        shift
        ;;
      -p|--print)
        action="print"
        shift
        ;;
      --refresh-prompt)
        refresh_prompt=1
        shift
        ;;
      -h|--help)
        print_ai_commit_help
        return 0
        ;;
      *)
        die "Unknown ai-commit option: $1"
        ;;
    esac
  done

  require_command git
  require_command jq
  require_command curl
  require_command base64

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
    die "Not inside a Git repository"

  if git diff --cached --quiet; then
    die "No staged changes found. Stage changes first with 'git add <files>'."
  fi

  [[ -n "$model" ]] || model="$(container_model)"

  AI_COMMIT_TMP="$(mktemp -d)"
  export AI_COMMIT_TMP
  trap 'rm -rf -- "${AI_COMMIT_TMP:-}"' EXIT

  local diff_file="$AI_COMMIT_TMP/staged.diff"
  local prompt_file="$AI_COMMIT_TMP/system-prompt.txt"
  local payload_file="$AI_COMMIT_TMP/request.json"
  local response_file="$AI_COMMIT_TMP/response.json"

  git diff --cached > "$diff_file"
  [[ -s "$diff_file" ]] || die "Failed to read staged diff"

  info "Analyzing staged changes with $model..."
  load_ai_commit_prompt "$refresh_prompt" > "$prompt_file"
  [[ -s "$prompt_file" ]] || die "Failed to load ai-commit prompt"

  jq -n \
    --arg model "$model" \
    --rawfile system "$prompt_file" \
    --rawfile diff "$diff_file" \
    '{
      model: $model,
      messages: [
        {role: "system", content: $system},
        {
          role: "user",
          content: ("Analyze the following git diff and generate a commit message:\n\n" + $diff)
        }
      ],
      stream: false,
      options: {
        temperature: 0.1,
        top_p: 0.9,
        top_k: 1
      }
    }' > "$payload_file"

  if ! curl --fail-with-body -sS \
      -H 'Content-Type: application/json' \
      -d @"$payload_file" \
      "$(api_url /api/chat)" > "$response_file"; then
    [[ ! -s "$response_file" ]] || cat "$response_file" >&2
    die "Ollama failed to generate a commit message"
  fi

  local commit_msg
  commit_msg="$(jq -er '.message.content // empty' "$response_file")" || {
    cat "$response_file" >&2
    die "Ollama response did not contain a commit message"
  }
  [[ -n "$commit_msg" ]] || die "Generated commit message is empty"

  if [[ "$action" == "print" ]]; then
    printf '%s\n' "$commit_msg"
    return 0
  fi

  printf '\n%s================ Generated Commit Message ================%s\n\n' "$YELLOW" "$RESET"
  printf '%s\n' "$commit_msg"
  printf '\n%s==========================================================%s\n\n' "$YELLOW" "$RESET"

  case "$action" in
    yes)
      commit_with_message_file "$commit_msg" 0
      ;;
    edit)
      commit_with_message_file "$commit_msg" 1
      ;;
    interactive)
      local choice=""
      if ! read -r -p "Do you want to commit with this message? (y/e/n) [y=yes, e=edit, n=no]: " choice; then
        choice="n"
      fi

      case "$choice" in
        y|Y) commit_with_message_file "$commit_msg" 0 ;;
        e|E) commit_with_message_file "$commit_msg" 1 ;;
        *) printf '%s\n' "Commit cancelled. Your changes remain staged." ;;
      esac
      ;;
  esac
}

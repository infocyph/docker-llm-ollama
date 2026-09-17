#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$LLM_SM_RUNTIME_ROOT/lib/commit.sh"

print_ai_commit_help() {
  cat <<'EOF'
Usage: llm-sm ai-commit [options]

Generate a commit message using llm-sm's bundled Conventional Commit + Gitmoji
prompt and local Ollama inference.

By default, staged changes are read from the current Git repository. This works
inside the published container when the repository is bind-mounted there.
Use --diff-stdin as a fallback when no repository mount is available.

Options:
  -m, --model <model>   Override the Ollama model
  -y, --yes             Commit immediately with the generated message
  -e, --edit            Open the generated message in $EDITOR, then commit
  -p, --print           Print only the generated message; do not commit
      --diff-stdin      Read the diff from stdin and print the generated message
  -h, --help            Show this help

Environment:
  LLM_SM_AI_COMMIT_PROMPT_FILE
                        Override the bundled prompt with another local file
EOF
}

git_cmd() {
  git -c safe.directory='*' "$@"
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
  git_cmd commit -F "$msg_file"
  info "Committed successfully."
}

command_main() {
  local model=""
  local action="interactive"
  local diff_stdin=0

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
      --diff-stdin)
        diff_stdin=1
        action="print"
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

  require_command jq
  require_command curl
  model="$(resolve_model "$model")"

  AI_COMMIT_TMP="$(mktemp -d)"
  export AI_COMMIT_TMP
  trap 'rm -rf -- "${AI_COMMIT_TMP:-}"' EXIT

  local diff_file="$AI_COMMIT_TMP/staged.diff"
  local prompt_file="$AI_COMMIT_TMP/system-prompt.txt"
  local payload_file="$AI_COMMIT_TMP/request.json"
  local response_file="$AI_COMMIT_TMP/response.json"

  if (( diff_stdin )); then
    [[ ! -t 0 ]] || die "--diff-stdin requires a diff on stdin"
    cat > "$diff_file"
  else
    require_command git
    git_cmd rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not inside a Git repository"
    if git_cmd diff --cached --quiet; then
      die "No staged changes found. Stage changes first with 'git add <files>'."
    fi
    git_cmd diff --cached > "$diff_file"
  fi

  [[ -s "$diff_file" ]] || die "No diff content found"
  check_file_budget "Git diff" "$diff_file"

  warn "Analyzing changes with $model..."
  load_ai_commit_prompt > "$prompt_file"
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

  if ! curl --connect-timeout 3 --fail-with-body -sS \
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

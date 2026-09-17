#!/usr/bin/env bash

command_main() {
  local model="" system input stdin_data file_data
  local -a files=()
  system="${LLM_SM_SYSTEM:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--model)
        [[ $# -ge 2 ]] || die "Missing model after $1"
        model="$2"
        shift 2
        ;;
      -s|--system)
        [[ $# -ge 2 ]] || die "Missing system prompt after $1"
        system="$2"
        shift 2
        ;;
      -f|--file)
        [[ $# -ge 2 ]] || die "Missing file after $1"
        files+=("$2")
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*) die "Unknown option: $1" ;;
      *) break ;;
    esac
  done

  model="$(resolve_model "$model")"
  input="${*:-}"
  stdin_data="$(read_stdin_if_piped)"
  file_data="$(file_context "${files[@]}")"

  if [[ -n "$stdin_data" ]]; then
    input+="${input:+$'\n\n'}--- STDIN ---"$'\n'"$stdin_data"
  fi
  if [[ -n "$file_data" ]]; then
    input+="${input:+$'\n\n'}$file_data"
  fi

  [[ -n "$input" ]] || die "Prompt, piped input, or --file is required"
  check_input_budget "Prompt input" "$input"
  run_text_prompt "$model" "$system" "$input"
}

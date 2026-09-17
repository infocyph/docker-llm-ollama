#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$LLM_SM_RUNTIME_ROOT/lib/attachments.sh"

command_main() {
  local model="" system input stdin_data file_data pdf_data attachment_tmp rendered kind
  local -a files=() images=() pdfs=() pdf_vision=() rendered_pages=()
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
      --image)
        [[ $# -ge 2 ]] || die "Missing image after $1"
        images+=("$2")
        shift 2
        ;;
      --pdf)
        [[ $# -ge 2 ]] || die "Missing PDF after $1"
        pdfs+=("$2")
        shift 2
        ;;
      --pdf-vision)
        [[ $# -ge 2 ]] || die "Missing PDF after $1"
        pdf_vision+=("$2")
        shift 2
        ;;
      --attach)
        [[ $# -ge 2 ]] || die "Missing attachment after $1"
        kind="$(attachment_kind "$2")"
        case "$kind" in
          image) images+=("$2") ;;
          unsupported-image) die "Unsupported image format for --attach: $2. Use PNG, JPEG, or WebP." ;;
          pdf) pdfs+=("$2") ;;
          text) files+=("$2") ;;
        esac
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
  pdf_data="$(pdf_text_context "${pdfs[@]}")"

  if [[ -n "$stdin_data" ]]; then
    input+="${input:+$'\n\n'}--- STDIN ---"$'\n'"$stdin_data"
  fi
  if [[ -n "$file_data" ]]; then
    input+="${input:+$'\n\n'}$file_data"
  fi
  if [[ -n "$pdf_data" ]]; then
    input+="${input:+$'\n\n'}$pdf_data"
  fi

  local image
  for image in "${images[@]}"; do
    validate_image_file "$image"
  done

  if (( ${#images[@]} > 0 || ${#pdf_vision[@]} > 0 )); then
    require_model "$model"
    require_model_capability "$model" vision
  fi

  if (( ${#pdf_vision[@]} > 0 )); then
    attachment_tmp="$(mktemp -d)"
    # Expand the generated temp path now so cleanup does not depend on local scope at shell exit.
    # shellcheck disable=SC2064
    trap "rm -rf -- $(printf '%q' "$attachment_tmp")" EXIT

    local index=0 pdf
    for pdf in "${pdf_vision[@]}"; do
      index=$((index + 1))
      rendered="$(render_pdf_pages "$pdf" "$attachment_tmp" "$index")"
      [[ -n "$rendered" ]] || die "PDF rendered no image pages: $pdf"
      mapfile -t rendered_pages <<< "$rendered"
      images+=("${rendered_pages[@]}")
      rendered_pages=()
    done
  fi

  if [[ -z "$input" && ${#images[@]} -gt 0 ]]; then
    input="Analyze the attached image content and answer concisely."
  fi

  [[ -n "$input" ]] || die "Prompt, piped input, --file, --pdf, --image, --pdf-vision, or --attach is required"
  check_input_budget "Prompt input" "$input"
  run_chat_prompt "$model" "$system" "$input" "${images[@]}"

  if [[ -n "${attachment_tmp:-}" ]]; then
    rm -rf -- "$attachment_tmp"
  fi
}

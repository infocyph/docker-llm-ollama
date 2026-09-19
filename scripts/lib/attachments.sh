#!/usr/bin/env bash

attachment_kind() {
  local path="${1:-}"
  local lower="${path,,}"

  case "$lower" in
    *.png|*.jpg|*.jpeg|*.webp) printf '%s\n' image ;;
    *.gif|*.bmp|*.tif|*.tiff|*.svg) printf '%s\n' unsupported-image ;;
    *.pdf) printf '%s\n' pdf ;;
    *) printf '%s\n' text ;;
  esac
}

validate_image_file() {
  local file="$1"
  local lower="${file,,}"

  [[ -f "$file" ]] || die "Image file not found: $file"
  [[ -s "$file" ]] || die "Image file is empty: $file"
  check_attachment_set "Image attachment" "$file"

  case "$lower" in
    *.png|*.jpg|*.jpeg|*.webp) ;;
    *) die "Unsupported image format: $file. Use PNG, JPEG, or WebP for Ollama vision input." ;;
  esac
}

pdf_text_context() {
  (( $# > 0 )) || return 0
  require_command pdftotext
  check_attachment_set "PDF text attachments" "$@"

  local file text first=1
  for file in "$@"; do
    [[ -f "$file" ]] || die "PDF file not found: $file"
    [[ -s "$file" ]] || die "PDF file is empty: $file"

    text="$(pdftotext -layout "$file" - 2>/dev/null)" || die "Failed to extract text from PDF: $file"
    if [[ -z "$(printf '%s' "$text" | tr -d '[:space:]')" ]]; then
      die "PDF has no extractable text: $file. Use --pdf-vision with a vision-capable model for scanned/image PDFs."
    fi

    if (( ! first )); then
      printf '\n\n'
    fi
    first=0

    printf '%s\n' "--- PDF: $file ---"
    printf '%s\n' "$text"
  done
}

pdf_page_count() {
  require_command pdfinfo
  local file="$1" pages
  [[ -f "$file" ]] || die "PDF file not found: $file"
  [[ -s "$file" ]] || die "PDF file is empty: $file"
  pages="$(LC_ALL=C pdfinfo "$file" 2>/dev/null | awk -F: '/^Pages:/ {gsub(/[[:space:]]/, "", $2); print $2; exit}')"
  [[ "$pages" =~ ^[1-9][0-9]*$ ]] || die "Unable to determine PDF page count: $file"
  printf '%s\n' "$pages"
}

check_pdf_vision_pages() {
  (( $# > 0 )) || return 0
  validate_attachment_limits
  local max_pages="${LLM_OLLAMA_PDF_MAX_PAGES:-$DEFAULT_PDF_MAX_PAGES}"
  local file pages total_pages=0
  for file in "$@"; do
    pages="$(pdf_page_count "$file")"
    total_pages=$((total_pages + pages))
  done
  if (( max_pages > 0 && total_pages > max_pages )) && ! large_input_allowed; then
    die "PDF vision input has ${total_pages} pages; page limit is ${max_pages}. Raise LLM_OLLAMA_PDF_MAX_PAGES, set it to 0, or use LLM_OLLAMA_ALLOW_LARGE_INPUT=1 deliberately."
  fi
}

render_pdf_pages() {
  require_command pdftoppm

  local file="$1"
  local out_dir="$2"
  local index="$3"
  local dpi="${LLM_OLLAMA_PDF_DPI:-120}"
  local prefix

  [[ -f "$file" ]] || die "PDF file not found: $file"
  [[ -s "$file" ]] || die "PDF file is empty: $file"
  check_attachment_set "PDF vision attachment" "$file"
  check_pdf_vision_pages "$file"
  [[ "$dpi" =~ ^[1-9][0-9]*$ ]] || die "LLM_OLLAMA_PDF_DPI must be a positive integer"

  mkdir -p "$out_dir"
  prefix="$out_dir/pdf-${index}"
  pdftoppm -png -r "$dpi" "$file" "$prefix" >/dev/null 2>&1 || die "Failed to render PDF pages: $file"

  find "$out_dir" -maxdepth 1 -type f -name "pdf-${index}-*.png" -print | sort -V
}

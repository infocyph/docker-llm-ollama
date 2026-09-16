#!/usr/bin/env bash

command_main() {
  [[ $# -le 1 ]] || die "Usage: llm-sm install [bin-directory]"
  require_command install
  require_command cp

  local target_dir="${1:-/usr/local/bin}"
  local prefix lib_target target_bin source_root use_sudo=0
  target_dir="${target_dir%/}"
  prefix="$(dirname -- "$target_dir")"
  lib_target="$prefix/lib/llm-sm"
  target_bin="$target_dir/llm-sm"
  source_root="$LLM_SM_RUNTIME_ROOT"

  mkdir -p -- "$target_dir" "$lib_target" 2>/dev/null || true
  if [[ ! -w "$target_dir" || ! -w "$lib_target" ]]; then
    command -v sudo >/dev/null 2>&1 || die "Installation requires write access or sudo: $prefix"
    use_sudo=1
    sudo install -d -m 0755 "$target_dir" "$lib_target"
  fi

  if (( use_sudo )); then
    if [[ "$LLM_SM_ENTRYPOINT" != "$target_bin" ]]; then
      sudo install -m 0755 "$LLM_SM_ENTRYPOINT" "$target_bin"
    fi
    if [[ "$source_root" != "$lib_target" ]]; then
      sudo rm -rf -- \
        "${lib_target:?}/lib" \
        "${lib_target:?}/commands" \
        "${lib_target:?}/prompts"
      sudo cp -R -- \
        "$source_root/lib" \
        "$source_root/commands" \
        "$source_root/prompts" \
        "$lib_target/"
      sudo chmod -R a+rX "$lib_target"
    fi
  else
    if [[ "$LLM_SM_ENTRYPOINT" != "$target_bin" ]]; then
      install -m 0755 "$LLM_SM_ENTRYPOINT" "$target_bin"
    fi
    if [[ "$source_root" != "$lib_target" ]]; then
      rm -rf -- \
        "${lib_target:?}/lib" \
        "${lib_target:?}/commands" \
        "${lib_target:?}/prompts"
      cp -R -- \
        "$source_root/lib" \
        "$source_root/commands" \
        "$source_root/prompts" \
        "$lib_target/"
      chmod -R a+rX "$lib_target"
    fi
  fi

  info "Installed: $target_bin"
  info "Modules:   $lib_target"
}

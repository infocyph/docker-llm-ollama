#!/usr/bin/env bash

command_main() {
  [[ $# -le 1 ]] || die "Usage: llm-sm uninstall [bin-directory]"

  local target_dir="${1:-/usr/local/bin}"
  local prefix lib_target target_bin use_sudo=0
  target_dir="${target_dir%/}"
  prefix="$(dirname -- "$target_dir")"
  lib_target="$prefix/lib/llm-sm"
  target_bin="$target_dir/llm-sm"

  [[ -e "$target_bin" || -d "$lib_target" ]] || die "llm-sm is not installed under: $prefix"

  if [[ ! -w "$target_dir" || ( -d "$lib_target" && ! -w "$lib_target" ) ]]; then
    command -v sudo >/dev/null 2>&1 || die "Removal requires write access or sudo: $prefix"
    use_sudo=1
  fi

  if (( use_sudo )); then
    sudo rm -f -- "$target_bin"
    sudo rm -rf -- "$lib_target"
  else
    rm -f -- "$target_bin"
    rm -rf -- "$lib_target"
  fi

  info "Removed: $target_bin"
  info "Removed: $lib_target"
}

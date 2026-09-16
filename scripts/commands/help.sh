#!/usr/bin/env bash

command_main() {
  cat <<EOF
${BOLD}llm-sm${RESET} - host CLI for the local Ollama small-model container

${BOLD}Usage:${RESET}
  llm-sm <command> [arguments]

${BOLD}Developer:${RESET}
  ask [-m model] <prompt>               Ask once
  chat [model]                          Start interactive chat
  prompt [options] <prompt>             Generic prompt with system/file context
  code [options] <task>                 Generate or improve code
  review [options] [file...] [focus]    Review code from files/stdin
  json [options] <prompt>               Native structured JSON output
  ai-commit [options]                   Generate commit message from staged diff

${BOLD}Model:${RESET}
  models                                List installed models
  ps                                    List loaded models
  run <model> [prompt...]               Run an explicit model
  show [model]                          Show model information
  pull <model>                          Pull a model
  rm <model>                            Remove a model
  unload [model]                        Unload a model from RAM/VRAM

${BOLD}Container:${RESET}
  status                                Show container/API/model status
  start                                 Start existing container
  stop                                  Stop container
  restart                               Restart container
  logs [docker-log-args...]             Follow/read container logs

${BOLD}Low level:${RESET}
  ollama <args...>                      Raw Ollama CLI passthrough
  api <path> [curl-args...]             Raw Ollama HTTP API call
  version                               Show CLI/Ollama versions

${BOLD}Host install:${RESET}
  install [bin-directory]               Install command + modules
  uninstall [bin-directory]             Remove installed command + modules

${BOLD}Common options:${RESET}
  -m, --model <model>                   Override model
  -f, --file <path>                     Add file context (prompt/code/review)

${BOLD}prompt options:${RESET}
  -s, --system <text>                   System-style instruction

${BOLD}json options:${RESET}
  --schema <file>                       Use JSON Schema as Ollama format
  -r, --response-only                   Print only validated model JSON (requires jq)

${BOLD}ai-commit options:${RESET}
  -y, --yes                             Commit generated message immediately
  -e, --edit                            Edit generated message before commit
  -p, --print                           Print generated message only

${BOLD}Environment:${RESET}
  LLM_SM_CONTAINER                      Container name (default: llm-sm)
  LLM_SM_URL                            API base URL (default: http://127.0.0.1:11434)
  LLM_SM_MODEL                          Default/fallback model (default: qwen2.5:3b)
  LLM_SM_SYSTEM                         Default system text for prompt
  LLM_SM_LIB_DIR                        Override installed module directory
  LLM_SM_AI_COMMIT_PROMPT_FILE          Override bundled ai-commit prompt file
  OLLAMA_PORT                           Port when LLM_SM_URL is unset
  NO_COLOR                              Disable colored output

${BOLD}Examples:${RESET}
  llm-sm ask "Explain PHP fibers briefly"
  llm-sm chat
  llm-sm prompt -s "Answer concisely" "Explain CQRS"
  llm-sm code -f src/Foo.php "Optimize this hot path"
  llm-sm review src/Foo.php "Focus on concurrency and resource leaks"
  cat src/Foo.php | llm-sm review
  llm-sm json -r "Return an object with name and version"
  llm-sm json --schema schema.json -r "Describe this service"
  git add . && llm-sm ai-commit
  llm-sm ai-commit --print
EOF
}

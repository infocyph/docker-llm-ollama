#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${1:-${LLM_SM_SMOKE_IMAGE:-llm-sm:runtime-smoke}}"
MODEL="${OLLAMA_MODEL:-qwen2.5:3b}"
suffix="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$"
container="llm-sm-smoke-${suffix}"
volume="llm-sm-smoke-${suffix}"
network="llm-sm-smoke-${suffix}"
tmp_dir="$(mktemp -d)"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "$1" >&2
    exit 1
  }
}

cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  docker volume rm "$volume" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

wait_healthy() {
  local status
  for _ in $(seq 1 90); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container" 2>/dev/null || true)"
    case "$status" in
      healthy) return 0 ;;
      unhealthy)
        docker logs "$container" >&2 || true
        printf 'Container became unhealthy.\n' >&2
        return 1
        ;;
    esac
    sleep 2
  done

  docker logs "$container" >&2 || true
  printf 'Timed out waiting for container health.\n' >&2
  return 1
}

start_container() {
  docker run -d \
    --name "$container" \
    --network "$network" \
    --network-alias llm-sm \
    --mount "type=volume,src=${volume},dst=/root/.ollama" \
    "$IMAGE" >/dev/null
  wait_healthy
}

peer_get() {
  local path="$1"
  docker run --rm \
    --network "$network" \
    --entrypoint curl \
    "$IMAGE" \
    --connect-timeout 3 -fsS "http://llm-sm:11434${path}"
}

require_command docker
require_command jq

docker image inspect "$IMAGE" >/dev/null
docker volume create "$volume" >/dev/null
docker network create "$network" >/dev/null

printf 'Starting fresh-volume runtime smoke for %s...\n' "$IMAGE"
start_container

docker exec "$container" command -v pdftotext >/dev/null
docker exec "$container" command -v pdftoppm >/dev/null

tags="$(docker exec "$container" curl --connect-timeout 3 -fsS http://127.0.0.1:11434/api/tags)"
jq -e --arg model "$MODEL" 'any(.models[]?; .name == $model or .model == $model)' <<<"$tags" >/dev/null

printf 'Validating internal Docker DNS without a host port mapping...\n'
peer_tags="$(peer_get /api/tags)"
jq -e --arg model "$MODEL" 'any(.models[]?; .name == $model or .model == $model)' <<<"$peer_tags" >/dev/null

generate_payload="$(jq -cn --arg model "$MODEL" '{model:$model,prompt:"Reply with OK only.",stream:false,options:{temperature:0}}')"
docker exec "$container" curl --connect-timeout 3 --fail-with-body -sS \
  -H 'Content-Type: application/json' \
  -d "$generate_payload" \
  http://127.0.0.1:11434/api/generate \
  | jq -e '.done == true and (.response | type == "string")' >/dev/null

chat_payload="$(jq -cn --arg model "$MODEL" '{model:$model,messages:[{role:"user",content:"Reply with OK only."}],stream:true,options:{temperature:0}}')"
stream_output="$(docker exec "$container" curl --connect-timeout 3 --fail-with-body -sS \
  -H 'Content-Type: application/json' \
  -d "$chat_payload" \
  http://127.0.0.1:11434/api/chat)"
jq -s -e 'length > 0 and any(.[]; .done == true)' <<<"$stream_output" >/dev/null

openai_payload="$(jq -cn --arg model "$MODEL" '{model:$model,messages:[{role:"user",content:"Reply with OK only."}],stream:false,temperature:0}')"
docker exec "$container" curl --connect-timeout 3 --fail-with-body -sS \
  -H 'Content-Type: application/json' \
  -d "$openai_payload" \
  http://127.0.0.1:11434/v1/chat/completions \
  | jq -e '.choices[0].message.content | type == "string"' >/dev/null

docker exec "$container" llm-sm models >/dev/null
docker exec "$container" llm-sm ask -m "$MODEL" 'Reply with OK only.' >/dev/null

if docker exec "$container" llm-sm ask -m llm-sm-smoke-model-does-not-exist 'test' >"$tmp_dir/missing.out" 2>"$tmp_dir/missing.err"; then
  printf 'Missing-model command unexpectedly succeeded.\n' >&2
  exit 1
fi
grep -q "is not installed. Run 'llm-sm pull" "$tmp_dir/missing.err"

docker exec "$container" sh -c 'printf smoke > /root/.ollama/.llm-sm-persistence-smoke'

printf 'Validating clean SIGTERM shutdown...\n'
docker stop --time 30 "$container" >/dev/null
test "$(docker inspect -f '{{.State.Running}}' "$container")" = false
test "$(docker inspect -f '{{.State.OOMKilled}}' "$container")" = false
docker rm "$container" >/dev/null

printf 'Recreating container with the same model volume...\n'
start_container
docker exec "$container" test -f /root/.ollama/.llm-sm-persistence-smoke

tags="$(docker exec "$container" curl --connect-timeout 3 -fsS http://127.0.0.1:11434/api/tags)"
jq -e --arg model "$MODEL" 'any(.models[]?; .name == $model or .model == $model)' <<<"$tags" >/dev/null
peer_get /api/tags >/dev/null

docker stop --time 30 "$container" >/dev/null
test "$(docker inspect -f '{{.State.Running}}' "$container")" = false
test "$(docker inspect -f '{{.State.OOMKilled}}' "$container")" = false

printf 'Runtime smoke passed for %s with model %s.\n' "$IMAGE" "$MODEL"

#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${1:-${LLM_SM_SMOKE_IMAGE:-llm-sm:runtime-smoke}}"
CANDIDATE_PROMPT="${2:-}"
RUNS="${LLM_SM_BENCHMARK_RUNS:-3}"
MODEL="${OLLAMA_MODEL:-qwen3:14b}"
name="llm-sm-prompt-bench-${GITHUB_RUN_ID:-local}-${RANDOM}"
tmp="$(mktemp -d)"

cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  rm -rf -- "$tmp"
}
trap cleanup EXIT

[[ "$RUNS" =~ ^[1-9][0-9]*$ ]] || { echo 'LLM_SM_BENCHMARK_RUNS must be a positive integer.' >&2; exit 1; }
docker image inspect "$IMAGE" >/dev/null

cat > "$tmp/fixture.diff" <<'EOF'
diff --git a/src/Cache.php b/src/Cache.php
index 1111111..2222222 100644
--- a/src/Cache.php
+++ b/src/Cache.php
@@ -10,7 +10,10 @@ final class Cache
-        return $this->store[$key] ?? null;
+        if (!array_key_exists($key, $this->store)) {
+            return null;
+        }
+        return $this->store[$key];
 }
EOF

docker run -d --name "$name" "$IMAGE" >/dev/null
for _ in $(seq 1 90); do
  status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$name" 2>/dev/null || true)"
  [[ "$status" == healthy ]] && break
  [[ "$status" == unhealthy ]] && { docker logs "$name" >&2 || true; exit 1; }
  sleep 2
done
[[ "$(docker inspect -f '{{.State.Health.Status}}' "$name")" == healthy ]]

if [[ -n "$CANDIDATE_PROMPT" ]]; then
  [[ -s "$CANDIDATE_PROMPT" ]] || { echo "Candidate prompt not found or empty: $CANDIDATE_PROMPT" >&2; exit 1; }
  docker cp "$CANDIDATE_PROMPT" "$name:/tmp/ai-commit-candidate.txt"
fi

header_ok() {
  local output="$1" first
  first="$(head -n 1 <<< "$output")"
  [[ "$first" =~ ^:[a-zA-Z0-9_+-]+:[[:space:]]+(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9-]+\))?!?:[[:space:]].+ ]]
}

container_file_bytes() {
  local path="$1"
  docker exec "$name" sh -c 'wc -c < "$1"' _ "$path" | tr -d '[:space:]'
}

run_case() {
  local label="$1" prompt_file="${2:-}" run start end elapsed output size

  if [[ -n "$prompt_file" ]]; then
    size="$(container_file_bytes "$prompt_file")"
  else
    size="$(container_file_bytes /usr/local/lib/llm-sm/prompts/ai-commit.txt)"
  fi

  for run in $(seq 1 "$RUNS"); do
    start="$(date +%s%3N)"
    if [[ -n "$prompt_file" ]]; then
      output="$(docker exec -i \
        -e LLM_SM_MODEL="$MODEL" \
        -e LLM_SM_AI_COMMIT_PROMPT_FILE="$prompt_file" \
        "$name" llm-sm ai-commit --diff-stdin --print < "$tmp/fixture.diff")"
    else
      output="$(docker exec -i -e LLM_SM_MODEL="$MODEL" \
        "$name" llm-sm ai-commit --diff-stdin --print < "$tmp/fixture.diff")"
    fi
    end="$(date +%s%3N)"
    elapsed=$((end - start))

    if header_ok "$output"; then
      printf '%s,%s,%s,%s,%s\n' "$label" "$run" "$elapsed" true "$size"
    else
      printf '%s,%s,%s,%s,%s\n' "$label" "$run" "$elapsed" false "$size"
      printf 'Invalid %s output on run %s:\n%s\n' "$label" "$run" "$output" >&2
      return 1
    fi
  done
}

printf 'case,run,elapsed_ms,header_ok,prompt_bytes\n'
run_case baseline
if [[ -n "$CANDIDATE_PROMPT" ]]; then
  run_case candidate /tmp/ai-commit-candidate.txt
fi

printf '\nBenchmark is a regression aid, not an automatic quality oracle. Review both latency and message quality before replacing the bundled prompt.\n' >&2

#!/usr/bin/env bash
# Run every BlenderLore task with one selected Harbor agent profile.
set -Eeuo pipefail
export DOCKER_BUILDKIT=0
export COMPOSE_DOCKER_CLI_BUILD=0

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${BLENDERLORE_DATA_DIR:-$ROOT/data}"
JOBS_DIR="${BLENDERLORE_JOBS_DIR:-$ROOT/../blenderlore-jobs}"
if [[ -n "${BLENDERLORE_PYTHON_BIN:-}" ]]; then
  PYTHON="$BLENDERLORE_PYTHON_BIN"
elif [[ -x /opt/conda/envs/blenderlore/bin/python ]]; then
  PYTHON="/opt/conda/envs/blenderlore/bin/python"
else
  PYTHON="$(command -v python3 || command -v python)"
fi
export PYTHONPATH="$ROOT:${PYTHONPATH:-}"
PROFILE="${1:-}"
shift || true
TEST_MODE="${BLENDERLORE_TEST:-0}"
PARALLEL="${BLENDERLORE_PARALLEL:-1}"
AUTO_JUDGE="${BLENDERLORE_AUTO_JUDGE:-1}"
FORWARDED_ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--test" ]]; then
    TEST_MODE=1
  else
    FORWARDED_ARGS+=("$arg")
  fi
done

case "$PROFILE" in
  codex-sol)   RUNNER="$ROOT/scripts/run_codex_sol.sh" ;;
  codex-astra) RUNNER="$ROOT/scripts/run_codex_astra.sh" ;;
  claude-fable) RUNNER="$ROOT/scripts/run_claude_fable.sh" ;;
  kimi-code)   RUNNER="$ROOT/scripts/run_kimi_code.sh" ;;
  *)
    echo "usage: $0 {codex-sol|codex-astra|claude-fable|kimi-code} [harbor args...]" >&2
    exit 2
    ;;
esac

[[ -d "$DATA_DIR" ]] || { echo "task directory not found: $DATA_DIR" >&2; exit 1; }
TASKS=()
while IFS= read -r task; do TASKS+=("$task"); done < <(find "$DATA_DIR" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort)
TOTAL="${#TASKS[@]}"

# BlenderLore source folders contain task assets but not Harbor's wrapper
# metadata. Materialize lightweight Harbor task directories on demand.
HARBOR_TASK_ROOT="${BLENDERLORE_HARBOR_TASK_ROOT:-$ROOT/.harbor_tasks}"
mkdir -p "$HARBOR_TASK_ROOT"
HARBOR_PATHS=()
harbor_index=0
for src in "${TASKS[@]}"; do
  name="$(basename "$src")"; dst="$HARBOR_TASK_ROOT/task_$(printf '%03d' "$harbor_index")"
  HARBOR_PATHS+=("$dst")
  harbor_index=$((harbor_index + 1))
  mkdir -p "$dst/environment" "$dst/tests" "$dst/solution"
  cp "$src/output/task.md" "$dst/instruction.md"
  cp -R "$src/input" "$dst/input" 2>/dev/null || true
  cat > "$dst/task.toml" <<'EOF'
schema_version = "1.4"
[metadata]
[verifier]
timeout_sec = 1800.0
[agent]
timeout_sec = 1800.0
[environment]
build_timeout_sec = 1200.0
EOF
  cat > "$dst/environment/Dockerfile" <<'EOF'
FROM ubuntu:22.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip ffmpeg git && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
EOF
  cat > "$dst/tests/test.sh" <<'EOF'
#!/usr/bin/env bash
set -e
mkdir -p /logs/verifier
echo 0 > /logs/verifier/reward.txt
EOF
  chmod +x "$dst/tests/test.sh"
done
(( TOTAL > 0 )) || { echo "no task directories found under $DATA_DIR" >&2; exit 1; }

if [[ "$TEST_MODE" == "1" ]]; then
  TEST_LIMIT=5
  if (( TOTAL > TEST_LIMIT )); then
    TASKS=("${TASKS[@]:0:TEST_LIMIT}")
  fi
fi
TOTAL="${#TASKS[@]}"

MODE="full"
[[ "$TEST_MODE" == "1" ]] && MODE="test"
if ! [[ "$PARALLEL" =~ ^[0-9]+$ ]] || (( PARALLEL < 1 )); then
  echo "BLENDERLORE_PARALLEL must be a positive integer, got: $PARALLEL" >&2
  exit 2
fi
if [[ "$AUTO_JUDGE" != "0" && "$AUTO_JUDGE" != "1" ]]; then
  echo "BLENDERLORE_AUTO_JUDGE must be 0 or 1, got: $AUTO_JUDGE" >&2
  exit 2
fi
echo "Running $TOTAL BlenderLore tasks with profile: $PROFILE (mode=$MODE, parallel=$PARALLEL, auto_judge=$AUTO_JUDGE)"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$JOBS_DIR"
MANIFEST="$JOBS_DIR/${RUN_ID}.jsonl"
printf '{"run_id":"%s","profile":"%s","total_tasks":%d,"started_at":"%s"}\n' "$RUN_ID" "$PROFILE" "$TOTAL" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MANIFEST"
RUN_ROOT="$JOBS_DIR/${RUN_ID}"
mkdir -p "$RUN_ROOT"

run_judge() {
  local index="$1"
  local task="$2"
  local submission_dir="$3"
  local eval_dir="$RUN_ROOT/${index}/evaluation"
  local eval_log="$RUN_ROOT/${index}/judge.log"
  local reward="null"
  local eval_status="skipped"
  if [[ "$AUTO_JUDGE" == "1" ]]; then
    mkdir -p "$eval_dir"
    eval_status="completed"
    if ! "$PYTHON" -m eval --task "$task" --submission "$submission_dir" --output "$eval_dir" >"$eval_log" 2>&1; then
      eval_status="failed"
    fi
    if [[ -f "$eval_dir/reward.txt" ]]; then
      reward="$(tr -d '[:space:]' < "$eval_dir/reward.txt")"
    fi
  fi
  printf '{"run_id":"%s","index":%d,"task_id":"%s","eval_status":"%s","reward":%s}\n' "$RUN_ID" "$((index + 1))" "$(basename "$task")" "$eval_status" "$reward" >> "$MANIFEST"
  printf "%s\n" "$eval_status" > "$RUN_ROOT/${index}.eval_status"
  printf "%s\n" "$reward" > "$RUN_ROOT/${index}.reward"
  [[ "$eval_status" != "failed" ]]
}

run_task() {
  local index="$1"
  task="${TASKS[$index]}"
  task_name="$(basename "$task")"
  echo "[$((index + 1))/$TOTAL] $task_name"
  task_status="completed"
  if [[ "${BLENDERLORE_DIRECT:-0}" == "1" ]]; then
    submission_dir="$RUN_ROOT/${index}/submission"
    mkdir -p "$submission_dir"
    if ! OPENAI_API_KEY="${OPENAI_API_KEY:?}" CODEX_MODEL="${CODEX_MODEL:-gpt-5.6-sol}" "$ROOT/scripts/run_codex_host.sh" "$task" "$submission_dir" >"$RUN_ROOT/${index}/agent.log" 2>&1; then
      task_status="failed"
    fi
  else
    harbor_task="${HARBOR_PATHS[$index]}"
    if ! "$RUNNER" -p "$harbor_task" --job-name "blenderlore-${PROFILE}-${RUN_ID}-${index}" "${FORWARDED_ARGS[@]}"; then
      task_status="failed"
      echo "[$((index + 1))/$TOTAL] FAILED: $task_name" >&2
    fi
  fi
  if [[ "$task_status" == "completed" && "${BLENDERLORE_DIRECT:-0}" == "1" ]]; then
    run_judge "$index" "$task" "$submission_dir" || true
  else
    printf "skipped\n" > "$RUN_ROOT/${index}.eval_status"
    printf "null\n" > "$RUN_ROOT/${index}.reward"
    printf '{"run_id":"%s","index":%d,"task_id":"%s","eval_status":"skipped","reward":null}\n' "$RUN_ID" "$((index + 1))" "$task_name" >> "$MANIFEST"
  fi
  printf '{"run_id":"%s","index":%d,"task_id":"%s","status":"%s"}\n' "$RUN_ID" "$((index + 1))" "$task_name" "$task_status" >> "$MANIFEST"
  printf "%s\n" "$task_status" > "$RUN_ROOT/${index}.status"
  [[ "$task_status" == "completed" ]]
}

failures=0
if (( PARALLEL == 1 )); then
  for index in "${!TASKS[@]}"; do
    run_task "$index" || true
  done
else
  running=0
  for index in "${!TASKS[@]}"; do
    run_task "$index" &
    running=$((running + 1))
    if (( running >= PARALLEL )); then
      wait -n || true
      running=$((running - 1))
    fi
  done
  while (( running > 0 )); do
    wait -n || true
    running=$((running - 1))
  done
fi

for index in "${!TASKS[@]}"; do
  if [[ "$(cat "$RUN_ROOT/${index}.status" 2>/dev/null || echo failed)" != "completed" ]]; then
    failures=$((failures + 1))
  fi
done
eval_failures=0
if [[ "$AUTO_JUDGE" == "1" ]]; then
  for index in "${!TASKS[@]}"; do
    if [[ "$(cat "$RUN_ROOT/${index}.eval_status" 2>/dev/null || echo failed)" == "failed" ]]; then
      eval_failures=$((eval_failures + 1))
    fi
  done
fi

echo "Completed $TOTAL tasks; failures=$failures eval_failures=$eval_failures"
printf '{"run_id":"%s","completed_tasks":%d,"failures":%d,"eval_failures":%d,"finished_at":"%s"}\n' "$RUN_ID" "$TOTAL" "$failures" "$eval_failures" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$MANIFEST"
(( failures == 0 && eval_failures == 0 ))

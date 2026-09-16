#!/usr/bin/env bash
# Run every BlenderLore task with one selected Harbor agent profile.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${BLENDERLORE_DATA_DIR:-$ROOT/data}"
JOBS_DIR="${BLENDERLORE_JOBS_DIR:-$ROOT/../blenderlore-jobs}"
PROFILE="${1:-}"
shift || true
TEST_MODE="${BLENDERLORE_TEST:-0}"
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
echo "Running $TOTAL BlenderLore tasks with profile: $PROFILE (mode=$MODE)"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$JOBS_DIR"
MANIFEST="$JOBS_DIR/${RUN_ID}.jsonl"
printf '{"run_id":"%s","profile":"%s","total_tasks":%d,"started_at":"%s"}\n' "$RUN_ID" "$PROFILE" "$TOTAL" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MANIFEST"
failures=0
for index in "${!TASKS[@]}"; do
  task="${TASKS[$index]}"
  task_name="$(basename "$task")"
  echo "[$((index + 1))/$TOTAL] $task_name"
  task_status="completed"
  if ! "$RUNNER" -p "$task" --job-name "blenderlore-${PROFILE}-${index}" "${FORWARDED_ARGS[@]}"; then
    failures=$((failures + 1))
    task_status="failed"
    echo "[$((index + 1))/$TOTAL] FAILED: $task_name" >&2
  fi
  printf '{"run_id":"%s","index":%d,"task_id":"%s","status":"%s"}\n' "$RUN_ID" "$((index + 1))" "$task_name" "$task_status" >> "$MANIFEST"
done

echo "Completed $TOTAL tasks; failures=$failures"
printf '{"run_id":"%s","completed_tasks":%d,"failures":%d,"finished_at":"%s"}\n' "$RUN_ID" "$TOTAL" "$failures" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$MANIFEST"
(( failures == 0 ))

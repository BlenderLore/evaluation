#!/usr/bin/env bash
# Run a BlenderLore Harbor task with Codex.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -f .venv/bin/activate ] && source .venv/bin/activate
[ -f /opt/blender/blenderlore-env.sh ] && source /opt/blender/blenderlore-env.sh
if [ -f .env ]; then set -a; source .env; set +a; fi
: "${OPENAI_API_KEY:?Set OPENAI_API_KEY for the Harbor Codex agent}"
export PYTHONPATH="$ROOT:${PYTHONPATH:-}"
: "${BLENDERLORE_JOBS_DIR:=$ROOT/../blenderlore-jobs}"
mkdir -p "$BLENDERLORE_JOBS_DIR"
agent_env=(--ae "OPENAI_API_KEY=$OPENAI_API_KEY")
if [ -n "${OPENAI_BASE_URL:-}" ]; then agent_env+=(--ae "OPENAI_BASE_URL=$OPENAI_BASE_URL"); fi
exec harbor run --jobs-dir "$BLENDERLORE_JOBS_DIR" \
  --agent-import-path harbor.agents.installed.codex:Codex \
  --model "${BLENDERLORE_AGENT_MODEL:-gpt-5.5}" \
  "${agent_env[@]}" --no-delete "$@"

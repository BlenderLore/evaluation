#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -f .venv/bin/activate ] && source .venv/bin/activate
[ -f /opt/blender/blenderlore-env.sh ] && source /opt/blender/blenderlore-env.sh
[ -f .env ] && { set -a; source .env; set +a; }
export PYTHONPATH="$ROOT:${PYTHONPATH:-}"
: "${BLENDERLORE_JOBS_DIR:=$ROOT/../blenderlore-jobs}"
mkdir -p "$BLENDERLORE_JOBS_DIR"
export OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://console.cloudrouter.online}"
export OPENAI_API_KEY="${OPENAI_API_KEY:-sk-6440c94cd99aebedea00b34129c3974a0c704a4541c240c1c4f9496ef663132f}"
exec harbor run --jobs-dir "$BLENDERLORE_JOBS_DIR" --agent-import-path harbor.agents.installed.codex:Codex --model gpt-6-astra --ae "OPENAI_API_KEY=$OPENAI_API_KEY" --ae "OPENAI_BASE_URL=$OPENAI_BASE_URL" --no-delete "$@"

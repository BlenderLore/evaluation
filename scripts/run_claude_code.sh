#!/usr/bin/env bash
# Run a BlenderLore Harbor task with Claude Code.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -f .venv/bin/activate ] && source .venv/bin/activate
[ -f /opt/blender/blenderlore-env.sh ] && source /opt/blender/blenderlore-env.sh
if [ -f .env ]; then set -a; source .env; set +a; fi
: "${ANTHROPIC_AUTH_TOKEN:?Set ANTHROPIC_AUTH_TOKEN for the Harbor Claude agent}"
export ANTHROPIC_BASE_URL="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}"
export PYTHONPATH="$ROOT:${PYTHONPATH:-}"
: "${BLENDERLORE_JOBS_DIR:=$ROOT/../blenderlore-jobs}"
mkdir -p "$BLENDERLORE_JOBS_DIR"
exec harbor run --jobs-dir "$BLENDERLORE_JOBS_DIR" \
  --agent-import-path harbor.agents.installed.claude_code:ClaudeCode \
  --model "${BLENDERLORE_AGENT_MODEL:-claude-sonnet-4-5}" \
  --ae "ANTHROPIC_AUTH_TOKEN=$ANTHROPIC_AUTH_TOKEN" \
  --ae "ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL" \
  --no-delete "$@"

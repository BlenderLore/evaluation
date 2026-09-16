#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -f .venv/bin/activate ] && source .venv/bin/activate
[ -f /opt/conda/bin/activate ] && { source /opt/conda/bin/activate blenderlore 2>/dev/null || true; }
[ -f /opt/blender/blenderlore-env.sh ] && source /opt/blender/blenderlore-env.sh
[ -f .env ] && { set -a; source .env; set +a; }
export PYTHONPATH="$ROOT:${PYTHONPATH:-}"
: "${BLENDERLORE_JOBS_DIR:=$ROOT/../blenderlore-jobs}"
mkdir -p "$BLENDERLORE_JOBS_DIR"
export ANTHROPIC_BASE_URL="${ANTHROPIC_BASE_URL:-https://console.cloudrouter.online}"
export ANTHROPIC_AUTH_TOKEN="${ANTHROPIC_AUTH_TOKEN:-sk-ef94b26ddf91bdc7fe8a16edc06f7ff54c9a34503471377508e575a4795629f3}"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CLAUDE_CODE_ATTRIBUTION_HEADER=0
exec harbor run --jobs-dir "$BLENDERLORE_JOBS_DIR" --agent-import-path harbor.agents.installed.claude_code:ClaudeCode --model claude-fable-5-1 --ae "ANTHROPIC_AUTH_TOKEN=$ANTHROPIC_AUTH_TOKEN" --ae "ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL" --ae CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 --ae CLAUDE_CODE_ATTRIBUTION_HEADER=0 --no-delete "$@"

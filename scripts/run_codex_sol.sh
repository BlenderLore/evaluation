#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export DOCKER_BUILDKIT=0
export COMPOSE_DOCKER_CLI_BUILD=0
[ -f .venv/bin/activate ] && source .venv/bin/activate
[ -f /opt/conda/bin/activate ] && { source /opt/conda/bin/activate blenderlore 2>/dev/null || true; }
[ -f /opt/blender/blenderlore-env.sh ] && source /opt/blender/blenderlore-env.sh
[ -f .env ] && { set -a; source .env; set +a; }
export PYTHONPATH="$ROOT:${PYTHONPATH:-}"
: "${BLENDERLORE_JOBS_DIR:=$ROOT/../blenderlore-jobs}"
mkdir -p "$BLENDERLORE_JOBS_DIR"
export OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://console.cloudrouter.online}"
export OPENAI_API_KEY="${OPENAI_API_KEY:-sk-5905ff850727afd7de635dbc91419a70d264eaa6f054c9974434e565f00c7925}"
exec harbor run --jobs-dir "$BLENDERLORE_JOBS_DIR" --agent codex --model gpt-5.6-sol --ae "OPENAI_API_KEY=$OPENAI_API_KEY" --ae "OPENAI_BASE_URL=$OPENAI_BASE_URL" --no-delete "$@"

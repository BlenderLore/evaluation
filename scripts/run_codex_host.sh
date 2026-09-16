#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_DIR="${1:?task directory required}"
WORK_DIR="${2:?submission directory required}"
MODEL="${CODEX_MODEL:-gpt-5.6-sol}"
mkdir -p "$WORK_DIR"
PROMPT="$(cat "$TASK_DIR/output/task.md")

Complete this BlenderLore task in the current workspace. Create build.py, submission.blend, and all required rendered evidence. Use Blender 5.1.2. Verify files exist before finishing."
export OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://console.cloudrouter.online/v1}"
export OPENAI_API_KEY="${OPENAI_API_KEY:?OPENAI_API_KEY must be set}"
CODEX_HOME_DIR="$WORK_DIR/.codex"
mkdir -p "$CODEX_HOME_DIR"
cat > "$CODEX_HOME_DIR/config.toml" <<EOF
model_provider = "cloudrouter"
model = "$MODEL"
model_reasoning_effort = "high"
disable_response_storage = true
network_access = "enabled"

[model_providers.cloudrouter]
name = "cloudrouter"
base_url = "$OPENAI_BASE_URL"
wire_api = "responses"
requires_openai_auth = true
EOF
export CODEX_HOME="$CODEX_HOME_DIR"
printf '{"OPENAI_API_KEY":"%s"}\n' "$OPENAI_API_KEY" > "$CODEX_HOME_DIR/auth.json"
exec codex exec --model "$MODEL" --cd "$WORK_DIR" --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "$PROMPT"

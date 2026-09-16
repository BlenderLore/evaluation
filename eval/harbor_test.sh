#!/usr/bin/env bash
# Harbor verifier entrypoint. Mount the task definition at /tests/task and the
# agent workspace at /workspace/submission.
set -u
mkdir -p /logs/verifier
PYTHON="${PYTHON:-python3}"
TASK_DIR="${BLENDERLORE_TASK_DIR:-/tests/task}"
SUBMISSION_DIR="${BLENDERLORE_SUBMISSION_DIR:-/workspace/submission}"
set +e
"$PYTHON" -m eval --task "$TASK_DIR" --submission "$SUBMISSION_DIR" --output /logs/verifier
rc=$?
set -e
[ -f /logs/verifier/reward.txt ] || echo 0 > /logs/verifier/reward.txt
exit 0

# BlenderLore Harbor evaluator

The evaluator is intentionally independent of the task content and of
`gamecraft-bench`. A task directory contains `output/task.md` and
`output/rubric.json`; an agent submission is supplied separately.

```bash
python -m eval \
  --task data/B36_玻璃猫爪挂件 \
  --submission /workspace/submission \
  --output /logs/verifier
```

Static tasks collect six rendered view images from the submission. Dynamic
tasks are identified by the task directory suffix `_dynamic`/`_动态`; they
collect the rendered MP4, probe it with `ffprobe`, and sample frames with
`ffmpeg` for the multimodal rubric judge. Results are written to `reward.txt` and
`breakdown.json`.

Set `BLENDERLORE_EVAL_JUDGE=stub` for an offline dry run, or provide
`OPENAI_API_KEY` for the default OpenAI judge. Blender, Blender Python,
EEVEE/Cycles, FFmpeg and FFprobe are recorded in the environment manifest;
the evaluator does not assume task-specific external packages.

## Runtime installation

Harbor images should install the runtime before launching a job:

```bash
sudo ./scripts/install_blender_runtime.sh
source /opt/blender/blenderlore-env.sh
```

Blender Python, EEVEE, and Cycles are distributed inside the Blender package;
only FFmpeg/FFprobe are installed as separate system packages. The installer
verifies the Blender version and writes the executable paths consumed by the
evaluator.

## Harbor agents

Agent credentials are separate from the Judge configuration. Use the provided
wrappers after installing Harbor and the runtime:

```bash
OPENAI_API_KEY=... ./scripts/run_codex.sh -p <task-path>
ANTHROPIC_AUTH_TOKEN=... ./scripts/run_claude_code.sh -p <task-path>
```

The wrappers use Harbor's installed `Codex` and `ClaudeCode` agent classes and
forward credentials with Harbor's `--ae` mechanism. Judge credentials remain
in `judge.yaml`.

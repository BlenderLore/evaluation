from __future__ import annotations

import argparse
from pathlib import Path

from .evaluator import evaluate_task


def main() -> int:
    p = argparse.ArgumentParser(description="Evaluate one BlenderLore Harbor task")
    p.add_argument("--task", type=Path, required=True)
    p.add_argument("--submission", type=Path, required=True,
                   help="Agent submission directory (submission.blend/build.py and rendered evidence)")
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--judge", default=None, choices=["openai", "stub"])
    args = p.parse_args()
    result = evaluate_task(args.task, args.output, submission_dir=args.submission, judge_backend=args.judge)
    evidence_count = len(result.evidence.files) if result.evidence else 0
    print(f"reward={result.reward:.6f} task_type={result.task_type} evidence={evidence_count} completion={result.metrics['completion']['status']}")
    return 0 if result.reward >= 0.5 else 1


if __name__ == "__main__":
    raise SystemExit(main())

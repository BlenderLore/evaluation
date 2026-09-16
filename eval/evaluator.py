from __future__ import annotations

import json
import time
from pathlib import Path

from .config import SETTINGS
from .environment import probe
from .judge import score
from .media import collect_six_views, collect_video, detect_task_type
from .models import CriterionScore, EvaluationResult


def _load_rubric(task_dir: Path) -> dict:
    path = task_dir / "output" / "rubric.json"
    if not path.exists():
        raise FileNotFoundError(path)
    return json.loads(path.read_text(encoding="utf-8"))


def evaluate_task(
    task_dir: str | Path,
    output_dir: str | Path,
    *,
    submission_dir: str | Path | None = None,
    judge_backend: str | None = None,
) -> EvaluationResult:
    task_dir, output_dir = Path(task_dir).resolve(), Path(output_dir).resolve()
    submission_dir = Path(submission_dir or task_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    rubric_doc = _load_rubric(task_dir)
    rubric = rubric_doc.get("rubric", rubric_doc.get("requirements", []))
    errors: list[str] = []
    task_type = detect_task_type(task_dir)
    evidence = None
    failure_type = None
    evidence_seconds = None
    judge_seconds = None
    try:
        evidence_started = time.monotonic()
        evidence = (
            collect_video(submission_dir, output_dir)
            if task_type == "dynamic"
            else collect_six_views(submission_dir, output_dir)
        )
        evidence_seconds = time.monotonic() - evidence_started
        judge_started = time.monotonic()
        scores, rationales, _raw = score(
            (task_dir / "output" / "task.md").read_text(encoding="utf-8"),
            rubric,
            evidence,
            backend=judge_backend or SETTINGS.judge_backend,
            model=SETTINGS.judge_model,
        )
        judge_seconds = time.monotonic() - judge_started
    except Exception as exc:
        errors.append(str(exc))
        failure_type = "evidence_or_judge_error"
        scores, rationales = {}, {}
    criteria = [CriterionScore(r["id"], float(r.get("points", 0)), scores.get(r["id"], 0.0), rationales.get(r["id"], "")) for r in rubric]
    total = float(rubric_doc.get("total_points", sum(c.points for c in criteria) or 1))
    reward = max(0.0, min(1.0, sum(c.points * c.normalized for c in criteria) / total))
    blend_exists = (submission_dir / "submission.blend").is_file()
    build_exists = (submission_dir / "build.py").is_file()
    if not blend_exists and not failure_type:
        failure_type = "missing_submission_blend"
    evidence_files = len(evidence.files) if evidence else 0
    metrics = {
        "completion": {"status": bool(evidence and not errors), "evidence_files": evidence_files},
        "build": {"submission_blend_present": blend_exists, "build_script_present": build_exists, "rebuild_executed": False},
        "render": {"status": bool(evidence), "static_view_count": evidence_files if task_type == "static" else None, "video_present": bool(evidence and task_type == "dynamic")},
        "deliverable": {"valid_evidence": bool(evidence), "submission_blend_present": blend_exists, "build_script_present": build_exists},
        "agent": {"steps": None, "turns": None, "tool_calls": None, "retries": None},
        "time_seconds": {"end_to_end": round(time.monotonic() - started, 3), "agent": None, "build": None, "render": round(evidence_seconds or 0.0, 3), "judge": round(judge_seconds or 0.0, 3)},
        "rubric": {"total_points": total, "capability_scores": _capability_scores(rubric, scores)},
        "tokens": {"agent_input": None, "agent_output": None, "judge_input": None, "judge_output": None, "total": None},
        "api": {"requests": None, "failed_requests": None, "retries": None},
        "failure_type": failure_type,
        "static": {"six_view_complete": task_type == "static" and evidence_files >= 6} if task_type == "static" else None,
        "dynamic": {"video_frame_count": evidence.metadata.get("frame_count") if evidence else 0, "video_metadata": evidence.metadata.get("ffprobe") if evidence else None} if task_type == "dynamic" else None,
    }
    result = EvaluationResult(task_dir.name, task_type, reward, evidence, tuple(criteria), tuple(errors), metrics)
    evidence_json = None if evidence is None else {"kind": evidence.kind, "files": [str(p) for p in evidence.files], "metadata": evidence.metadata}
    breakdown = {
        "task_id": result.task_id,
        "task_type": result.task_type,
        "reward": reward,
        "environment": probe(),
        "evidence": evidence_json,
        "criteria": [c.__dict__ for c in criteria],
        "errors": errors,
        "metrics": metrics,
    }
    (output_dir / "breakdown.json").write_text(
        json.dumps(breakdown, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (output_dir / "reward.txt").write_text(f"{reward:.6f}\n", encoding="utf-8")
    return result


def _capability_scores(rubric: list[dict], scores: dict[str, float]) -> dict[str, float]:
    totals: dict[str, float] = {}
    earned: dict[str, float] = {}
    for item in rubric:
        capability = str(item.get("capability", "uncategorized"))
        points = float(item.get("points", 0))
        totals[capability] = totals.get(capability, 0.0) + points
        earned[capability] = earned.get(capability, 0.0) + points * float(scores.get(item["id"], 0.0))
    return {key: round(earned[key] / value, 4) if value else 0.0 for key, value in totals.items()}

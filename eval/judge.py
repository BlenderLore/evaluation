from __future__ import annotations

import base64
import json
import os
from pathlib import Path

from .models import Evidence
from .config import SETTINGS


def _image_uri(path: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode()


def _prompt(task_md: str, rubric: list[dict], evidence: Evidence) -> str:
    criteria = [{"id": item["id"], "points": item.get("points", 0), "criterion": item.get("criterion", ""), "scoring_rule": item.get("scoring_rule", {})} for item in rubric]
    sections = [
        "You are evaluating a BlenderLore Blender task. Use only the supplied evidence.",
        "Return strict JSON with scores (0..1) and rationales keyed by criterion id.",
        "A score of 1 means PASS, 0.5 PARTIAL, and 0 FAIL according to scoring_rule.",
        f"Evidence kind: {evidence.kind}",
        f"Task instructions:\n{task_md[:20000]}",
        f"Rubric:\n{json.dumps(criteria, ensure_ascii=False)}",
        f"Video metadata:\n{json.dumps(evidence.metadata, ensure_ascii=False)}",
    ]
    return "\n\n".join(sections)


def _decode_response(raw: str) -> dict[str, object]:
    text = raw.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[-1].rsplit("```", 1)[0].strip()
    parsed = json.loads(text)
    if not isinstance(parsed, dict):
        raise ValueError("judge response must be a JSON object")
    return parsed


def score(
    task_md: str,
    rubric: list[dict],
    evidence: Evidence,
    *,
    backend: str,
    model: str,
) -> tuple[dict[str, float], dict[str, str], str]:
    if backend == "stub":
        return ({r["id"]: 0.0 for r in rubric}, {r["id"]: "stub judge" for r in rubric}, "stub")
    try:
        from openai import OpenAI
    except ImportError as exc:
        raise RuntimeError("openai package is required, or set BLENDERLORE_EVAL_JUDGE=stub") from exc
    api_key = SETTINGS.judge_api_key or os.environ.get("OPENAI_API_KEY") or os.environ.get("BLENDERLORE_OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is not set")
    content: list[dict] = [{"type": "text", "text": _prompt(task_md, rubric, evidence)}]
    for path in evidence.files:
        content.append({"type": "image_url", "image_url": {"url": _image_uri(path)}})
    client_kwargs = {"api_key": api_key}
    if base_url := (SETTINGS.judge_base_url or os.environ.get("OPENAI_BASE_URL")):
        client_kwargs["base_url"] = base_url
    client = OpenAI(**client_kwargs)
    response = client.chat.completions.create(
        model=model,
        messages=[{"role": "system", "content": "Be a strict visual rubric evaluator."}, {"role": "user", "content": content}],
        temperature=0,
        max_tokens=4096,
    )
    raw = response.choices[0].message.content or "{}"
    parsed = _decode_response(raw)
    scores = {str(k): max(0.0, min(1.0, float(v))) for k, v in parsed.get("scores", {}).items()}
    return scores, {str(k): str(v) for k, v in parsed.get("rationales", {}).items()}, raw

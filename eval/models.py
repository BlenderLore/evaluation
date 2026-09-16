from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal

TaskType = Literal["static", "dynamic"]


@dataclass(frozen=True)
class Evidence:
    kind: Literal["six_view", "video"]
    files: tuple[Path, ...]
    metadata: dict[str, object] = field(default_factory=dict)


@dataclass(frozen=True)
class CriterionScore:
    criterion_id: str
    points: float
    score: float
    rationale: str = ""

    @property
    def normalized(self) -> float:
        """Normalized judge score in the canonical [0, 1] range."""
        return max(0.0, min(1.0, float(self.score)))


@dataclass(frozen=True)
class EvaluationResult:
    task_id: str
    task_type: TaskType
    reward: float
    evidence: Evidence | None
    criteria: tuple[CriterionScore, ...]
    errors: tuple[str, ...] = ()
    metrics: dict[str, object] = field(default_factory=dict)

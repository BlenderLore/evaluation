"""Process-level configuration for the BlenderLore evaluator."""
from __future__ import annotations

import os
import shutil
from dataclasses import dataclass
from pathlib import Path


def _judge_file() -> dict[str, str]:
    path = Path(os.getenv("BLENDERLORE_JUDGE_CONFIG", "judge.yaml"))
    if not path.is_file():
        return {}
    try:
        import yaml
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        judge = data.get("judge", {})
        return judge if isinstance(judge, dict) else {}
    except ImportError:
        values: dict[str, str] = {}
        in_judge = False
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip() == "judge:":
                in_judge = True
                continue
            if in_judge and line.startswith("  ") and ":" in line:
                key, value = line.strip().split(":", 1)
                values[key.strip()] = value.strip().strip("'\"")
        return values
    except (OSError, ValueError):
        return {}


_JUDGE = _judge_file()


def _tool(env: str, command: str) -> str | None:
    return os.getenv(env) or shutil.which(command)


@dataclass(frozen=True)
class Settings:
    blender: str | None = _tool("BLENDERLORE_BLENDER_BIN", "blender")
    ffmpeg: str | None = _tool("BLENDERLORE_FFMPEG_BIN", "ffmpeg")
    ffprobe: str | None = _tool("BLENDERLORE_FFPROBE_BIN", "ffprobe")
    judge_backend: str = os.getenv("BLENDERLORE_EVAL_JUDGE", str(_JUDGE.get("provider", "openai"))).casefold()
    judge_model: str = os.getenv("BLENDERLORE_EVAL_JUDGE_MODEL", str(_JUDGE.get("model", "gpt-5.5")))
    judge_base_url: str | None = os.getenv("BLENDERLORE_JUDGE_BASE_URL", _JUDGE.get("base_url"))
    judge_api_key: str | None = os.getenv("BLENDERLORE_JUDGE_API_KEY", _JUDGE.get("api_key"))
    blender_version: str = "5.1.2"
    sample_fps: float = 2.0
    max_frames: int = 32


SETTINGS = Settings()
SIX_VIEWS = ("front", "back", "left", "right", "top", "bottom")


def environment_manifest() -> dict[str, object]:
    return {"blender": SETTINGS.blender, "blender_python": True, "blender_version_expected": SETTINGS.blender_version, "eevee": True, "cycles": True, "ffmpeg": SETTINGS.ffmpeg, "ffprobe": SETTINGS.ffprobe}

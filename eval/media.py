"""Discover and prepare evidence from an agent submission directory."""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

from .config import SETTINGS, SIX_VIEWS
from .models import Evidence

IMAGE_EXTENSIONS = frozenset({".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff"})
VIEW_PATTERNS = {name: re.compile(rf"(?:^|[-_ .]){re.escape(name)}(?:[-_ .]|$)", re.I) for name in SIX_VIEWS}


def detect_task_type(task_dir: Path) -> str:
    return "dynamic" if task_dir.name.casefold().endswith(("_dynamic", "_动态")) else "static"


def _run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=True, capture_output=True, text=True)


def collect_six_views(submission_dir: Path) -> Evidence:
    images = sorted(path for path in submission_dir.rglob("*") if path.is_file() and path.suffix.casefold() in IMAGE_EXTENSIONS)
    selected = [next((path for path in images if VIEW_PATTERNS[name].search(path.stem)), None) for name in SIX_VIEWS]
    selected = [path for path in selected if path is not None]
    selected.extend(path for path in images if path not in selected)
    if len(selected) < 6:
        raise ValueError(f"expected six submitted view images, found {len(images)}")
    return Evidence("six_view", tuple(selected[:6]), {"views": list(SIX_VIEWS)})


def collect_video(submission_dir: Path, artifact_dir: Path) -> Evidence:
    videos = sorted(path for path in submission_dir.rglob("*.mp4") if path.is_file())
    if not videos:
        raise ValueError("dynamic submission does not contain an MP4 render")
    if not SETTINGS.ffmpeg:
        raise ValueError("ffmpeg is not installed")
    video = videos[0]
    frames_dir = artifact_dir / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    try:
        _run([SETTINGS.ffmpeg, "-y", "-i", str(video), "-vf", f"fps={SETTINGS.sample_fps}", str(frames_dir / "frame_%05d.png")])
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ValueError(f"ffmpeg frame extraction failed: {exc}") from exc
    frames = tuple(sorted(frames_dir.glob("frame_*.png")))[: SETTINGS.max_frames]
    if not frames:
        raise ValueError("ffmpeg produced no frames")
    metadata: dict[str, object] = {"video": str(video), "frame_count": len(frames)}
    if SETTINGS.ffprobe:
        try:
            result = _run([SETTINGS.ffprobe, "-v", "error", "-show_streams", "-show_format", "-of", "json", str(video)])
            metadata["ffprobe"] = json.loads(result.stdout)
        except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
            metadata["ffprobe_error"] = str(exc)
    return Evidence("video", (video, *frames), metadata)

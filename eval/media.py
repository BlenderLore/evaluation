"""Discover and prepare evidence from an agent submission directory."""
from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path

from .config import SETTINGS, SIX_VIEWS
from .models import Evidence

IMAGE_EXTENSIONS = frozenset({".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff"})
VIEW_PATTERNS = {name: re.compile(rf"(?:^|[-_ .]){re.escape(name)}(?:[-_ .]|$)", re.I) for name in SIX_VIEWS}


def detect_task_type(task_dir: Path) -> str:
    return "dynamic" if task_dir.name.casefold().endswith(("_dynamic", "_动态")) else "static"


def _run(command: list[str], env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=True, capture_output=True, text=True, env=env)


def _render_six_views(submission_dir: Path, artifact_dir: Path) -> tuple[Path, ...]:
    """Render canonical orthographic views from the submitted blend file."""
    blend = submission_dir / "submission.blend"
    if not blend.is_file() or not SETTINGS.blender:
        return ()
    artifact_dir.mkdir(parents=True, exist_ok=True)
    script = artifact_dir / "render_six_views.py"
    out_dir = artifact_dir / "six_views"
    script.write_text("""
import bpy, math, os
from mathutils import Vector
out = os.environ['BLENDERLORE_VIEW_OUT']
os.makedirs(out, exist_ok=True)
scene = bpy.context.scene
objs = [o for o in scene.objects if o.type in {'MESH','CURVE','SURFACE','META','FONT'} and o.visible_get() and o.name != 'Studio_Floor']
if not objs: raise RuntimeError('submission has no renderable objects')
corners=[]
for o in objs:
    for c in o.bound_box:
        corners.append(o.matrix_world @ Vector(c))
lo=Vector((min(v.x for v in corners),min(v.y for v in corners),min(v.z for v in corners)))
hi=Vector((max(v.x for v in corners),max(v.y for v in corners),max(v.z for v in corners)))
center=(lo+hi)/2; extent=max((hi-lo).x,(hi-lo).y,(hi-lo).z,1e-3)
cam=bpy.data.objects.get('__BlenderLoreEvalCamera') or bpy.data.cameras.new('__BlenderLoreEvalCamera')
if not hasattr(cam,'data'): cam=bpy.data.objects.new('__BlenderLoreEvalCamera',cam)
if cam.name not in scene.collection.objects: scene.collection.objects.link(cam)
cam.data.type='ORTHO'; cam.data.ortho_scale=extent*1.25; cam.data.clip_start=0.001; cam.data.clip_end=max(1000.0, extent*10.0); scene.camera=cam
scene.render.engine='CYCLES'; scene.cycles.samples=32; scene.cycles.use_denoising=True; scene.render.resolution_x=768; scene.render.resolution_y=768; scene.render.resolution_percentage=100
if not scene.world: scene.world=bpy.data.worlds.new('EvalWorld')
scene.world.use_nodes=True; bg=scene.world.node_tree.nodes.get('Background');
if bg: bg.inputs[0].default_value=(0.8,0.8,0.8,1.0); bg.inputs[1].default_value=1.0
scene.render.image_settings.file_format='PNG'; scene.render.film_transparent=False
views={'front':((0,-1,0),(0,0,1)),'back':((0,1,0),(0,0,1)),'left':((-1,0,0),(0,0,1)),'right':((1,0,0),(0,0,1)),'top':((0,0,1),(0,1,0)),'bottom':((0,0,-1),(0,-1,0))}
for name,(direction,up) in views.items():
    d=Vector(direction); cam.location=center+d*extent*2.5; cam.rotation_euler=d.to_track_quat('-Z','Y').to_euler(); scene.render.filepath=os.path.join(out,name+'.png'); bpy.ops.render.render(write_still=True)
""", encoding='utf-8')
    env = dict(os.environ, BLENDERLORE_VIEW_OUT=str(out_dir))
    try:
        _run([SETTINGS.blender, "-b", str(blend), "--python", str(script)], env=env)
    except (OSError, subprocess.CalledProcessError):
        return ()
    return tuple(out_dir / f"{name}.png" for name in SIX_VIEWS if (out_dir / f"{name}.png").is_file())


def collect_six_views(submission_dir: Path, artifact_dir: Path | None = None) -> Evidence:
    images = sorted(
        path for path in submission_dir.rglob("*")
        if path.is_file()
        and path.suffix.casefold() in IMAGE_EXTENSIONS
        and not any(part.startswith(".") for part in path.relative_to(submission_dir).parts)
    )
    selected = [next((path for path in images if VIEW_PATTERNS[name].search(path.stem)), None) for name in SIX_VIEWS]
    selected = [path for path in selected if path is not None]
    selected.extend(path for path in images if path not in selected)
    if len(selected) < 6 and artifact_dir is not None:
        rendered = _render_six_views(submission_dir, artifact_dir)
        if len(rendered) == 6:
            return Evidence("six_view", rendered, {"views": list(SIX_VIEWS), "generated_from_blend": True})
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

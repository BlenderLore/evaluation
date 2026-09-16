"""Read-only probes for the Harbor runtime image."""
from __future__ import annotations

import subprocess

from .config import SETTINGS, environment_manifest


def probe() -> dict[str, object]:
    result = environment_manifest()
    if SETTINGS.blender:
        try:
            completed = subprocess.run([SETTINGS.blender, "--version"], check=True, capture_output=True, text=True, timeout=15)
            result["blender_version"] = completed.stdout.splitlines()[0] if completed.stdout else ""
            result["blender_version_ok"] = SETTINGS.blender_version in completed.stdout
        except (OSError, subprocess.SubprocessError) as exc:
            result["blender_error"] = str(exc)
    return result

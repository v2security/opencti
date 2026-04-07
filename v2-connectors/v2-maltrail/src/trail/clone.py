"""Git clone + rotate directories for maltrail data.

Directory layout inside data_dir:
  maltrail-old/   — previous run's data
  maltrail-new/   — current run's data (freshly cloned)
  maltrail-repo/  — temporary clone (removed after copy)
"""

from __future__ import annotations

import logging
import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from config import TRAIL_LABELS

logger = logging.getLogger(__name__)

_DIR_CLONE = "maltrail-repo"
_DIR_FIRST = "maltrail-first"
_DIR_NEW = "maltrail-new"
_DIR_OLD = "maltrail-old"


@dataclass
class CloneResult:
    """Outcome of a clone + rotate operation."""

    new_dir: str
    old_dir: str  # empty string on first run
    first_run: bool


def clone_and_rotate(repo_url: str, data_dir: str) -> CloneResult:
    """Perform directory rotation then a shallow git clone.

    1. Delete old, rename new → old
    2. git clone --depth 1
    3. Copy malware/malicious/suspicious into new directory
    4. Remove the clone
    """
    data_path = Path(data_dir)
    data_path.mkdir(parents=True, exist_ok=True)

    clone_dir = str(data_path / _DIR_CLONE)
    first_dir = str(data_path / _DIR_FIRST)
    new_dir = str(data_path / _DIR_NEW)
    old_dir = str(data_path / _DIR_OLD)

    target_dir, first_run = _rotate(first_dir, new_dir, old_dir)
    os.makedirs(target_dir, exist_ok=True)

    # Remove stale clone if it exists
    if os.path.isdir(clone_dir):
        shutil.rmtree(clone_dir)

    logger.info("Cloning %s", repo_url)
    subprocess.run(
        ["git", "clone", "--depth", "1", repo_url, clone_dir],
        check=True,
        capture_output=True,
        text=True,
    )

    # Copy trail categories from clone into target
    for label in TRAIL_LABELS:
        src = os.path.join(clone_dir, "trails", "static", label)
        dst = os.path.join(target_dir, label)
        if not os.path.isdir(src):
            logger.warning("Source folder missing: %s", src)
            continue
        shutil.copytree(src, dst, dirs_exist_ok=True)

    # Clean up clone
    shutil.rmtree(clone_dir, ignore_errors=True)

    result = CloneResult(new_dir=target_dir, old_dir="", first_run=first_run)
    if not first_run:
        result.old_dir = old_dir
    return result


def _rotate(
    first_dir: str, new_dir: str, old_dir: str
) -> tuple[str, bool]:
    """Handle 3-state directory rotation. Returns (target_dir, first_run)."""
    has_old = os.path.isdir(old_dir)
    has_new = os.path.isdir(new_dir)
    has_first = os.path.isdir(first_dir)

    if not has_old and not has_new and not has_first:
        # Very first run
        return first_dir, True

    if has_first and not has_old and not has_new:
        # Second run: promote first → old
        os.rename(first_dir, old_dir)
        return new_dir, False

    # Normal rotation: rm old → mv new → old → clone into new
    if has_old:
        shutil.rmtree(old_dir)
    if has_new:
        os.rename(new_dir, old_dir)
    return new_dir, False

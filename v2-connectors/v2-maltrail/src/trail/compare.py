"""SHA256-based comparison of old vs new trail directories."""

from __future__ import annotations

import hashlib
import logging
import os
from dataclasses import dataclass, field
from pathlib import Path

logger = logging.getLogger(__name__)


@dataclass
class Diff:
    """Result of comparing old vs new trail directories."""

    changed: list[str] = field(default_factory=list)  # relative paths of changed .txt files
    all: bool = False  # True when all files should be processed (first run)


def compare(old_dir: str, new_dir: str) -> Diff:
    """Walk new_dir and diff each .txt file against old_dir using SHA256.

    Returns Diff with all=True if old_dir is empty (first run).
    """
    if not old_dir or not os.path.isdir(old_dir):
        return Diff(all=True)

    changed: list[str] = []
    new_path = Path(new_dir)

    for root, _dirs, files in os.walk(new_dir):
        for name in files:
            if not name.lower().endswith(".txt"):
                continue

            full_path = os.path.join(root, name)
            rel = os.path.relpath(full_path, new_dir)
            old_path = os.path.join(old_dir, rel)

            if not os.path.isfile(old_path) or _files_differ(old_path, full_path):
                changed.append(rel)

    changed.sort()
    return Diff(changed=changed)


def _files_differ(a: str, b: str) -> bool:
    """Compare two files by size first, then SHA256 hash."""
    try:
        stat_a = os.stat(a)
        stat_b = os.stat(b)
    except OSError:
        return True

    if stat_a.st_size != stat_b.st_size:
        return True

    return _sha256sum(a) != _sha256sum(b)


def _sha256sum(path: str) -> str:
    """Return hex-encoded SHA256 digest of a file."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

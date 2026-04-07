"""Parse maltrail .txt files into IOC map (value → label).

Each .txt file contains one IOC per line. Lines starting with # or //
are comments. Ports (:NNN) and CIDR (/NN) suffixes are stripped.
Lines containing brackets are skipped.
"""

from __future__ import annotations

import logging
import os
import re
from pathlib import Path

from config import TRAIL_LABELS
from trail.compare import Diff

logger = logging.getLogger(__name__)

# Simple patterns to classify IOC type
_IPV4_RE = re.compile(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$")


def parse(base_dir: str, diff: Diff) -> dict[str, str]:
    """Read trail .txt files and return deduplicated map of IOC value → label.

    If diff.all is True, all files under base_dir are read;
    otherwise only diff.changed files.
    """
    if diff.all:
        return _parse_all(base_dir)
    return _parse_changed(base_dir, diff.changed)


def group_by_label(ioc_map: dict[str, str]) -> dict[str, list[str]]:
    """Invert IOC map into label → [values]."""
    result: dict[str, list[str]] = {label: [] for label in TRAIL_LABELS}
    for value, label in ioc_map.items():
        if label in result:
            result[label].append(value)
    return result


def classify_ioc(value: str) -> str:
    """Return 'ipv4' or 'domain' for the given IOC value."""
    if _IPV4_RE.match(value):
        return "ipv4"
    return "domain"


def _parse_all(base_dir: str) -> dict[str, str]:
    """Parse all .txt files under every label directory."""
    ioc_map: dict[str, str] = {}
    for label in TRAIL_LABELS:
        label_dir = os.path.join(base_dir, label)
        if not os.path.isdir(label_dir):
            continue
        for root, _dirs, files in os.walk(label_dir):
            for name in files:
                if not name.lower().endswith(".txt"):
                    continue
                path = os.path.join(root, name)
                _scan_file(path, label, ioc_map)
    return ioc_map


def _parse_changed(base_dir: str, changed_files: list[str]) -> dict[str, str]:
    """Parse only the changed .txt files."""
    ioc_map: dict[str, str] = {}
    seen: set[str] = set()

    for rel in changed_files:
        clean = os.path.normpath(rel.strip())
        if not clean or clean == ".":
            continue
        if clean in seen:
            continue
        seen.add(clean)

        label = _label_from_path(clean)
        if not label:
            continue

        path = os.path.join(base_dir, clean)
        _scan_file(path, label, ioc_map)

    return ioc_map


def _scan_file(path: str, label: str, out: dict[str, str]) -> None:
    """Read one .txt file and add cleaned IOC values to the map."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                value = _clean_line(line)
                if value:
                    out[value] = label
    except FileNotFoundError:
        pass
    except OSError:
        logger.warning("Failed to read %s", path)


def _clean_line(line: str) -> str:
    """Extract an IOC value (IP or domain) from a raw text line.

    Strips comments (#, //), ports (:NNN), CIDR (/NN), and lines with brackets.
    """
    line = line.strip()
    if not line or line[0] == "#" or line.startswith("//"):
        return ""
    if any(c in line for c in "[]\\"):
        return ""
    # Strip CIDR notation
    slash_idx = line.find("/")
    if slash_idx != -1:
        line = line[:slash_idx]
    # Strip port
    colon_idx = line.find(":")
    if colon_idx != -1:
        line = line[:colon_idx]
    return line.strip()


def _label_from_path(rel: str) -> str:
    """Extract the label from a relative path like 'malware/emotet.txt'."""
    parts = Path(rel).parts
    if not parts:
        return ""
    first = parts[0]
    if first in TRAIL_LABELS:
        return first
    return ""

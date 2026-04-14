"""Parse maltrail .txt files into IOC map.

Each .txt file contains one IOC per line. Lines starting with # or //
are comments; inline # comments are also stripped.
Ports (:NNN) and CIDR (/NN) suffixes are stripped.
Lines containing brackets are skipped.

Returns: dict[str, IOCEntry] mapping each IOC value to its classification.
"""

from __future__ import annotations

import logging
import os
import re
from dataclasses import dataclass
from pathlib import Path

from config import TRAIL_FOLDERS
from trail.compare import Diff
from trail.label_map import IOCGroupInfo, lookup

logger = logging.getLogger(__name__)

# Simple patterns to classify IOC type
_IPV4_RE = re.compile(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$")


@dataclass(frozen=True)
class IOCEntry:
    """Parsed IOC with full classification from label_map."""
    folder: str         # "malware", "malicious", "suspicious", "root"
    file_tag: str       # e.g. "emotet", "lockbit", "mass_scanner"
    info: IOCGroupInfo  # layer, group, score, kill_chain

# Simple patterns to classify IOC type
_IPV4_RE = re.compile(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$")


def parse(
    base_dir: str, diff: Diff, root_file_label: str = "suspicious"
) -> dict[str, IOCEntry]:
    """Read trail .txt files and return deduplicated map of value -> IOCEntry.

    If diff.all is True, all files under base_dir are read;
    otherwise only diff.changed files.
    """
    if diff.all:
        return _parse_all(base_dir, root_file_label)
    return _parse_changed(base_dir, diff.changed, root_file_label)


def group_by_group(ioc_map: dict[str, IOCEntry]) -> dict[str, list[str]]:
    """Group IOC values by their IOC group (e.g. dst.malware, dst.ransomware)."""
    result: dict[str, list[str]] = {}
    for value, entry in ioc_map.items():
        group = entry.info.group
        if group not in result:
            result[group] = []
        result[group].append(value)
    return result


def classify_ioc(value: str) -> str:
    """Return 'ipv4' or 'domain' for the given IOC value."""
    if _IPV4_RE.match(value):
        return "ipv4"
    return "domain"


def _file_tag_from_name(filename: str) -> str:
    """Extract a semantic tag from filename, e.g. 'emotet.txt' -> 'emotet'."""
    stem = Path(filename).stem
    return stem.lower().strip() if stem else ""


def _parse_all(base_dir: str, root_file_label: str) -> dict[str, IOCEntry]:
    """Parse all .txt files under every label directory and root level."""
    ioc_map: dict[str, IOCEntry] = {}

    # Parse files inside label sub-directories
    for folder in TRAIL_FOLDERS:
        label_dir = os.path.join(base_dir, folder)
        if not os.path.isdir(label_dir):
            continue
        for root, _dirs, files in os.walk(label_dir):
            for name in files:
                if not name.lower().endswith(".txt"):
                    continue
                path = os.path.join(root, name)
                file_tag = _file_tag_from_name(name)
                info = lookup(file_tag, folder)
                _scan_file(path, folder, file_tag, info, ioc_map)

    # Parse root-level .txt files (e.g. mass_scanner.txt)
    for name in sorted(os.listdir(base_dir)):
        path = os.path.join(base_dir, name)
        if os.path.isfile(path) and name.lower().endswith(".txt"):
            file_tag = _file_tag_from_name(name)
            info = lookup(file_tag, "root")
            _scan_file(path, "root", file_tag, info, ioc_map)

    return ioc_map


def _parse_changed(
    base_dir: str, changed_files: list[str], root_file_label: str
) -> dict[str, IOCEntry]:
    """Parse only the changed .txt files."""
    ioc_map: dict[str, IOCEntry] = {}
    seen: set[str] = set()

    for rel in changed_files:
        clean = os.path.normpath(rel.strip())
        if not clean or clean == ".":
            continue
        if clean in seen:
            continue
        seen.add(clean)

        folder, file_tag = _folder_from_path(clean, root_file_label)
        if not folder:
            continue

        info = lookup(file_tag, folder)
        path = os.path.join(base_dir, clean)
        _scan_file(path, folder, file_tag, info, ioc_map)

    return ioc_map


def _scan_file(
    path: str, folder: str, file_tag: str, info: IOCGroupInfo,
    out: dict[str, IOCEntry],
) -> None:
    """Read one .txt file and add cleaned IOC values to the map."""
    entry = IOCEntry(folder=folder, file_tag=file_tag, info=info)
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                value = _clean_line(line)
                if value:
                    out[value] = entry
    except FileNotFoundError:
        pass
    except OSError:
        logger.warning("Failed to read %s", path)


def _clean_line(line: str) -> str:
    """Extract an IOC value (IP or domain) from a raw text line.

    Strips comments (#, //), inline # comments, ports (:NNN),
    CIDR (/NN), and lines with brackets.
    """
    line = line.strip()
    if not line or line[0] == "#" or line.startswith("//"):
        return ""
    if any(c in line for c in "[]\\"):
        return ""
    # Strip inline comments (e.g. "1.2.3.4 # scanner")
    hash_idx = line.find("#")
    if hash_idx != -1:
        line = line[:hash_idx].strip()
        if not line:
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


def _folder_from_path(rel: str, root_file_label: str) -> tuple[str, str]:
    """Extract (folder, file_tag) from a relative path.

    Examples:
        'malware/emotet.txt'  -> ('malware', 'emotet')
        'mass_scanner.txt'    -> ('root', 'mass_scanner')
    """
    parts = Path(rel).parts
    if not parts:
        return ("", "")
    filename = parts[-1]
    file_tag = _file_tag_from_name(filename)
    # Root-level file (no parent directory)
    if len(parts) == 1:
        return ("root", file_tag)
    first = parts[0]
    if first in TRAIL_FOLDERS:
        return (first, file_tag)
    return ("", "")

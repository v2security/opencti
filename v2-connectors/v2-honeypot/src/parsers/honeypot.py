"""
Parser for the V2Secure honeypot CSV log.

CSV columns: time, source_ip, ip_reputation, country, protocol, port

Maps each `ip_reputation` value to one of the IOC groups defined in
docs/IOC_Label_Classification.md (all src-ioc — inbound traffic):

    Anonymizer      -> src.anonymizer
    Tor Exit Node   -> src.anonymizer
    Bot, Crawler    -> src.bot
    Mass Scanner    -> src.scanner
    Known Attacker  -> src.attacker

Rows are deduplicated by `source_ip`. For each IP we keep the latest hit
time and accumulate the set of observed (protocol, port) pairs and
countries to enrich the indicator description.
"""

from __future__ import annotations

import csv
import logging
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Iterable

logger = logging.getLogger(__name__)

_IPV4_RE = re.compile(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$")


# ---------------------------------------------------------------------------
# IOC group classification (mirrors trail.label_map.IOCGroupInfo)
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class IOCGroupInfo:
    """Complete classification for one honeypot IOC."""
    layer: str       # "src-ioc"
    group: str       # e.g. "src.scanner"
    score: int       # x_opencti_score (0-100)
    kill_chain: str  # MITRE ATT&CK phase_name
    tactic_id: str   # MITRE ATT&CK tactic ID


GROUP_META: dict[str, IOCGroupInfo] = {
    "src.scanner":    IOCGroupInfo("src-ioc", "src.scanner",    60, "reconnaissance",   "TA0043"),
    "src.attacker":   IOCGroupInfo("src-ioc", "src.attacker",   90, "initial-access",   "TA0001"),
    "src.bot":        IOCGroupInfo("src-ioc", "src.bot",        55, "reconnaissance",   "TA0043"),
    "src.anonymizer": IOCGroupInfo("src-ioc", "src.anonymizer", 50, "defense-evasion",  "TA0005"),
}


# Map raw reputation string (case-insensitive, trimmed) to an IOC group.
_REPUTATION_MAP: dict[str, str] = {
    "anonymizer":     "src.anonymizer",
    "tor exit node":  "src.anonymizer",
    "bot, crawler":   "src.bot",
    "bot,crawler":    "src.bot",
    "bot crawler":    "src.bot",
    "mass scanner":   "src.scanner",
    "known attacker": "src.attacker",
}


def classify_reputation(reputation: str) -> IOCGroupInfo:
    """Map an `ip_reputation` cell value to an IOCGroupInfo.

    Unknown values fall back to ``src.attacker`` (the most common case
    in the honeypot feed) so they are still imported with a reasonable
    score.
    """
    key = (reputation or "").strip().lower()
    group = _REPUTATION_MAP.get(key, "src.attacker")
    return GROUP_META[group]


# ---------------------------------------------------------------------------
# Parsed records
# ---------------------------------------------------------------------------

@dataclass
class HoneypotRecord:
    """Deduplicated honeypot observation for a single source IP."""
    source_ip: str
    reputation: str                     # original CSV value (for description)
    info: IOCGroupInfo                  # classification
    first_seen: datetime
    last_seen: datetime
    countries: set[str] = field(default_factory=set)
    services: set[str] = field(default_factory=set)   # "PROTOCOL/PORT" strings
    hit_count: int = 0


# ---------------------------------------------------------------------------
# CSV parsing
# ---------------------------------------------------------------------------

def parse_csv(file_path: str) -> list[HoneypotRecord]:
    """Read the honeypot CSV and return one record per unique source IP."""
    records: dict[str, HoneypotRecord] = {}

    try:
        fp = open(file_path, encoding="utf-8", newline="")
    except FileNotFoundError:
        logger.error("Honeypot CSV not found at %s", file_path)
        return []

    with fp as f:
        reader = csv.DictReader(f)
        for row in reader:
            rec = _row_to_record(row, records)
            if rec is None:
                continue

    logger.info(
        "Parsed %d unique honeypot IPs from %s", len(records), file_path
    )
    return list(records.values())


def group_by_group(records: Iterable[HoneypotRecord]) -> dict[str, list[str]]:
    """Group source IPs by their IOC group (src.scanner, src.attacker, ...)."""
    result: dict[str, list[str]] = {}
    for rec in records:
        result.setdefault(rec.info.group, []).append(rec.source_ip)
    return result


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

def _row_to_record(
    row: dict[str, str], records: dict[str, HoneypotRecord]
) -> HoneypotRecord | None:
    source_ip = (row.get("source_ip") or "").strip()
    if not source_ip or not _IPV4_RE.match(source_ip):
        return None

    reputation = (row.get("ip_reputation") or "").strip()
    info = classify_reputation(reputation)
    seen_at = _parse_time(row.get("time"))
    country = (row.get("country") or "").strip()
    protocol = (row.get("protocol") or "").strip().upper()
    port = (row.get("port") or "").strip()

    rec = records.get(source_ip)
    if rec is None:
        rec = HoneypotRecord(
            source_ip=source_ip,
            reputation=reputation,
            info=info,
            first_seen=seen_at,
            last_seen=seen_at,
        )
        records[source_ip] = rec
    else:
        if seen_at < rec.first_seen:
            rec.first_seen = seen_at
        if seen_at > rec.last_seen:
            rec.last_seen = seen_at
        # Promote to higher-severity reputation if encountered later
        if info.score > rec.info.score:
            rec.info = info
            rec.reputation = reputation

    if country:
        rec.countries.add(country)
    if protocol:
        rec.services.add(f"{protocol}/{port}" if port else protocol)
    rec.hit_count += 1
    return rec


def _parse_time(value: str | None) -> datetime:
    """Parse the CSV time column; fall back to "now" on failure."""
    if value:
        try:
            return datetime.strptime(
                value.strip(), "%Y-%m-%d %H:%M:%S"
            ).replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    return datetime.now(timezone.utc)

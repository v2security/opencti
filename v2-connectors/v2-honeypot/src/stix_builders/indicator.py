"""STIX2 Indicator builder for V2Secure honeypot IOCs."""

from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Any

from stix2 import ExternalReference, Identity, Indicator, KillChainPhase

from config import STIX_NAMESPACE
from parsers.honeypot import HoneypotRecord

# Source-label prefix used in every label list (per IOC_Label_Classification.md)
SOURCE_LABEL = "v2-honeypot"

_AUTHOR = Identity(
    id="identity--" + str(uuid.uuid5(STIX_NAMESPACE, "V2 Secure")),
    name="V2 Secure",
    identity_class="organization",
)


def get_author() -> Identity:
    """Return the V2 Secure author Identity."""
    return _AUTHOR


def build_labels(record: HoneypotRecord) -> list[str]:
    """6-label scheme: org / source / ioc-marker / layer / group / tactic-id."""
    return [
        "v2secure",
        SOURCE_LABEL,
        "v2-ioc",
        record.info.layer,
        record.info.group,
        record.info.tactic_id,
    ]


def _build_description(record: HoneypotRecord) -> str:
    parts = [
        f"V2Secure honeypot observation: {record.source_ip} classified as "
        f"{record.info.group} ({record.reputation})."
    ]
    if record.countries:
        parts.append(f"Countries: {', '.join(sorted(record.countries))}")
    if record.services:
        services = sorted(record.services)
        # Cap services list to keep description compact
        if len(services) > 10:
            services = services[:10] + ["…"]
        parts.append(f"Observed services: {', '.join(services)}")
    parts.append(
        f"Hits: {record.hit_count}, "
        f"first seen: {record.first_seen.isoformat()}, "
        f"last seen: {record.last_seen.isoformat()}"
    )
    return " ".join(parts)


def create_indicator(record: HoneypotRecord, valid_days: int) -> Indicator:
    """Create a STIX Indicator for one honeypot source IP."""
    pattern = f"[ipv4-addr:value = '{record.source_ip}']"
    valid_from = record.last_seen
    valid_until = valid_from + timedelta(days=valid_days)

    indicator_id = "indicator--" + str(
        uuid.uuid5(STIX_NAMESPACE, f"ipv4:{record.source_ip}")
    )

    kill_chain_phases = [
        KillChainPhase(
            kill_chain_name="mitre-attack",
            phase_name=record.info.kill_chain,
        )
    ]
    external_references = [
        ExternalReference(
            source_name="mitre-attack",
            external_id=record.info.tactic_id,
            url=f"https://attack.mitre.org/tactics/{record.info.tactic_id}/",
        )
    ]

    kwargs: dict[str, Any] = {
        "id": indicator_id,
        "name": record.source_ip,
        "description": _build_description(record),
        "pattern": pattern,
        "pattern_type": "stix",
        "valid_from": valid_from,
        "valid_until": valid_until,
        "created": record.first_seen,
        "modified": record.last_seen,
        "created_by_ref": _AUTHOR.id,
        "confidence": 100,
        "revoked": False,
        "indicator_types": ["malicious-activity"],
        "kill_chain_phases": kill_chain_phases,
        "external_references": external_references,
        "labels": build_labels(record),
        "x_opencti_score": record.info.score,
        "x_opencti_detection": True,
        "x_opencti_main_observable_type": "IPv4-Addr",
        "allow_custom": True,
    }
    return Indicator(**kwargs)

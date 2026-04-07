"""STIX2 Indicator builder for maltrail IOCs."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from stix2 import Identity, Indicator, KillChainPhase

from config import LABEL_SCORES, STIX_NAMESPACE

_AUTHOR = Identity(
    id="identity--" + str(uuid.uuid5(STIX_NAMESPACE, "V2 Secure")),
    name="V2 Secure",
    identity_class="organization",
)

_KILL_CHAIN_PHASES = [
    KillChainPhase(
        kill_chain_name="mitre-attack",
        phase_name="command-and-control",
    )
]


def get_author() -> Identity:
    return _AUTHOR


def create_indicator(
    value: str,
    label: str,
    ioc_type: str,
    valid_days: int = 30,
    file_tag: str = "",
) -> Indicator:
    """Create a STIX Indicator from a maltrail IOC.

    Args:
        value: IOC value (IP address or domain name).
        label: Trail category (malware, malicious, suspicious).
        ioc_type: 'ipv4' or 'domain'.
        valid_days: Indicator validity period in days.
        file_tag: Semantic tag from the source filename (e.g. 'emotet', 'bad_wpad').
    """
    now = datetime.now(timezone.utc)
    valid_from = now.isoformat(timespec="milliseconds").replace("+00:00", "Z")
    valid_until = (now + timedelta(days=valid_days)).isoformat(
        timespec="milliseconds"
    ).replace("+00:00", "Z")

    # Deterministic ID based on IOC value + label
    dedup_key = f"{ioc_type}:{value}:{label}"
    indicator_id = "indicator--" + str(uuid.uuid5(STIX_NAMESPACE, dedup_key))

    if ioc_type == "ipv4":
        pattern = f"[ipv4-addr:value = '{value}']"
        main_observable_type = "IPv4-Addr"
    else:
        pattern = f"[domain-name:value = '{value}']"
        main_observable_type = "Domain-Name"

    score = LABEL_SCORES.get(label, 50)

    labels = ["v2 secure", "maltrail", label]

    if file_tag:
        description = (
            f"Maltrail threat intelligence: {value} classified as {label} ({file_tag})."
        )
    else:
        description = (
            f"Maltrail threat intelligence: {value} classified as {label}."
        )

    kwargs: dict[str, Any] = {
        "id": indicator_id,
        "name": value,
        "description": description,
        "pattern": pattern,
        "pattern_type": "stix",
        "valid_from": valid_from,
        "valid_until": valid_until,
        "created": valid_from,
        "modified": valid_from,
        "created_by_ref": _AUTHOR.id,
        "confidence": 100,
        "revoked": False,
        "indicator_types": ["malicious-activity"],
        "kill_chain_phases": _KILL_CHAIN_PHASES,
        "labels": labels,
        "x_opencti_score": score,
        "x_opencti_detection": True,
        "x_opencti_main_observable_type": main_observable_type,
        "allow_custom": True,
    }

    return Indicator(**kwargs)

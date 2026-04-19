"""STIX2 Indicator builder for maltrail IOCs."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from stix2 import ExternalReference, Identity, Indicator, KillChainPhase

from config import STIX_NAMESPACE
from trail.label_map import IOCGroupInfo

_AUTHOR = Identity(
    id="identity--" + str(uuid.uuid5(STIX_NAMESPACE, "v2secure")),
    name="v2secure",
    identity_class="organization",
)


def get_author() -> Identity:
    return _AUTHOR


def create_indicator(
    value: str,
    info: IOCGroupInfo,
    ioc_type: str,
    valid_days: int = 30,
    file_tag: str = "",
) -> Indicator:
    """Create a STIX Indicator from a maltrail IOC.

    Args:
        value: IOC value (IP address or domain name).
        info: IOCGroupInfo with layer, group, score, kill_chain.
        ioc_type: 'ipv4' or 'domain'.
        valid_days: Indicator validity period in days.
        file_tag: Semantic tag from the source filename (e.g. 'emotet', 'bad_wpad').
    """
    now = datetime.now(timezone.utc)
    valid_from = now.isoformat(timespec="milliseconds").replace("+00:00", "Z")
    valid_until = (now + timedelta(days=valid_days)).isoformat(
        timespec="milliseconds"
    ).replace("+00:00", "Z")

    # Deterministic ID based on IOC value + group
    dedup_key = f"{ioc_type}:{value}:{info.group}"
    indicator_id = "indicator--" + str(uuid.uuid5(STIX_NAMESPACE, dedup_key))

    if ioc_type == "ipv4":
        pattern = f"[ipv4-addr:value = '{value}']"
        main_observable_type = "IPv4-Addr"
    else:
        pattern = f"[domain-name:value = '{value}']"
        main_observable_type = "Domain-Name"

    # 4 labels: org, source, layer, group
    labels = ["v2secure", "v2-ioc", info.layer, info.group]

    # Per-group kill chain phase
    kill_chain_phases = [
        KillChainPhase(
            kill_chain_name="mitre-attack",
            phase_name=info.kill_chain,
        )
    ]

    # MITRE ATT&CK tactic external reference
    external_references = [
        ExternalReference(
            source_name="mitre-attack",
            external_id=info.tactic_id,
            url=f"https://attack.mitre.org/tactics/{info.tactic_id}/",
        )
    ]

    if file_tag:
        description = (
            f"Maltrail threat intelligence: {value} classified as "
            f"{info.group} ({file_tag})."
        )
    else:
        description = (
            f"Maltrail threat intelligence: {value} classified as {info.group}."
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
        "kill_chain_phases": kill_chain_phases,
        "external_references": external_references,
        "labels": labels,
        "x_opencti_score": info.score,
        "x_opencti_detection": True,
        "x_opencti_main_observable_type": main_observable_type,
        "allow_custom": True,
    }

    return Indicator(**kwargs)

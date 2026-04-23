"""STIX2 Observable (IPv4Address) builder for V2Secure honeypot IOCs."""

from __future__ import annotations

import uuid
from typing import Any

from stix2 import IPv4Address

from config import STIX_NAMESPACE
from parsers.honeypot import HoneypotRecord
from stix_builders.indicator import build_labels, get_author


def create_observable(record: HoneypotRecord) -> IPv4Address:
    """Create an IPv4-Addr observable for one honeypot source IP."""
    observable_id = "ipv4-addr--" + str(
        uuid.uuid5(STIX_NAMESPACE, record.source_ip)
    )
    description = (
        f"V2Secure honeypot {record.info.group} ({record.reputation}): "
        f"{record.source_ip}"
    )
    kwargs: dict[str, Any] = {
        "id": observable_id,
        "value": record.source_ip,
        "created_by_ref": get_author().id,
        "labels": build_labels(record),
        "x_opencti_score": record.info.score,
        "x_opencti_description": description,
        "allow_custom": True,
    }
    return IPv4Address(**kwargs)

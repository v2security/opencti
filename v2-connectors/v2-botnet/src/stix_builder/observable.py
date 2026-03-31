"""STIX2 Observable builder for botnet IOCs."""

from __future__ import annotations

import json
import uuid

from stix2 import IPv4Address

from stix_builder.indicator import STIX_NAMESPACE, get_author


def create_observable(parsed: dict) -> IPv4Address | None:
    """Create an IPv4-Addr observable. Description is the raw source JSON."""
    source_ip = (parsed.get("source_ip") or "").strip()
    if not source_ip:
        return None

    observable_id = "ipv4-addr--" + str(uuid.uuid5(STIX_NAMESPACE, source_ip))

    source_json = {}
    for key in ("source_ip", "source_port", "source_asn", "source_isp",
                "country_iso", "city"):
        val = parsed.get(key)
        if val is not None and val != "":
            # Remap to clean field names
            clean_key = key.replace("source_", "") if key.startswith("source_") else key
            source_json[clean_key] = val

    kwargs = {
        "id": observable_id,
        "value": source_ip,
        "created_by_ref": get_author().id,
        "allow_custom": True,
        "x_opencti_score": 100,
        "x_opencti_description": json.dumps(source_json, ensure_ascii=False),
    }

    return IPv4Address(**kwargs)

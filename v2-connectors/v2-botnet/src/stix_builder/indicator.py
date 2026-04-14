"""STIX2 Indicator builder for botnet IOCs."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from typing import Any

from stix2 import ExternalReference, Identity, Indicator, KillChainPhase

try:
    import pycountry as _pycountry
except ImportError:
    import logging as _logging
    _logging.getLogger(__name__).warning(
        "pycountry not installed — country names will fall back to ISO codes"
    )
    _pycountry = None

# Deterministic namespace for botnet indicators
STIX_NAMESPACE = uuid.UUID("b1a2c3d4-e5f6-7890-abcd-ef1234567890")

_AUTHOR = Identity(
    id="identity--" + str(uuid.uuid5(STIX_NAMESPACE, "v2secure")),
    name="v2secure",
    identity_class="organization",
)

# Botnet IPs are short-lived — expire after 30 days
_VALID_UNTIL_DAYS = 30

_KILL_CHAIN_PHASES = [
    KillChainPhase(
        kill_chain_name="mitre-attack",
        phase_name="command-and-control",
    )
]


def get_author() -> Identity:
    return _AUTHOR


def _country_name(iso: str) -> str:
    if _pycountry is None:
        return iso
    try:
        c = _pycountry.countries.get(alpha_2=iso.upper())
        return c.name if c else iso
    except Exception:
        return iso


def build_description(parsed: dict) -> str:
    family = parsed.get("malware_family", "")
    variant = parsed.get("malware_variant", "")
    ip = parsed.get("source_ip", "")
    event_type = parsed.get("event_type", "")
    country_iso = parsed.get("country_iso", "")
    city = parsed.get("city", "")
    isp = parsed.get("source_isp", "")
    asn = parsed.get("source_asn")

    host_part = f"A host ({ip})" if ip else "A host"

    country_name = _country_name(country_iso) if country_iso else ""
    geo_parts = [p for p in [city, country_name] if p]
    geo_part = f" in {', '.join(geo_parts)}" if geo_parts else ""

    isp_parts = []
    if isp:
        isp_parts.append(isp)
    if asn is not None:
        isp_parts.append(f"ASN {asn}")
    isp_part = f" ({', '.join(isp_parts)})" if isp_parts else ""

    malware_str = f"{family}/{variant}" if (family and variant) else family
    malware_part = f" has been identified as infected with {malware_str} malware" if malware_str else ""

    traffic_part = f", with malicious activity observed over {event_type} traffic" if event_type else ""

    return f"{host_part}{geo_part}{isp_part}{malware_part}{traffic_part}."


def build_valid_until(timestamp: str, days: int = _VALID_UNTIL_DAYS) -> str:
    dt = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    until = dt + timedelta(days=days)
    return until.isoformat(timespec="milliseconds").replace("+00:00", "Z")



def create_indicator(parsed: dict) -> Indicator | None:
    source_ip = (parsed.get("source_ip") or "").strip()
    if not source_ip:
        return None

    event_id = parsed.get("id", "")
    timestamp = parsed.get("timestamp", "")
    malware_family = parsed.get("malware_family", "")

    valid_until = None
    if timestamp:
        try:
            valid_until = build_valid_until(timestamp)
        except (ValueError, OverflowError):
            pass

    name = source_ip

    # Use event_id for uniqueness, fall back to timestamp, then ip+family
    _dedup_key = event_id or (f"{source_ip}:{timestamp}" if timestamp else f"{source_ip}:{malware_family}" if malware_family else source_ip)
    indicator_id = "indicator--" + str(uuid.uuid5(STIX_NAMESPACE, _dedup_key))

    labels = ["v2secure", "v2-botnet", "src-ioc", "src.bot"]
    if malware_family:
        labels.append(f"malware-family:{malware_family}")
    malware_variant = parsed.get("malware_variant", "")
    if malware_variant:
        labels.append(f"malware-variant:{malware_variant}")

    ext_refs = []
    if event_id:
        ext_refs.append(
            ExternalReference(
                source_name="v2secure",
                external_id=event_id,
            )
        )

    pattern = f"[ipv4-addr:value = '{source_ip}']"

    kwargs: dict[str, Any] = {
        "id": indicator_id,
        "name": name,
        "description": build_description(parsed),
        "pattern": pattern,
        "pattern_type": "stix",
        "valid_from": timestamp,
        "valid_until": valid_until,
        "created": timestamp,
        "modified": timestamp,
        "created_by_ref": _AUTHOR.id,
        "confidence": 100,
        "revoked": False,
        "indicator_types": ["malicious-activity"],
        "kill_chain_phases": _KILL_CHAIN_PHASES,
        "labels": labels,
        "external_references": ext_refs,
        "x_opencti_score": 100,
        "x_opencti_detection": True,
        "x_opencti_main_observable_type": "IPv4-Addr",
        "allow_custom": True,
    }

    return Indicator(**kwargs)

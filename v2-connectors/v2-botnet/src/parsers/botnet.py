"""Parser for botnet JSON events (events[] format)."""
from __future__ import annotations

import logging

logger = logging.getLogger(__name__)



def get_malware(event: dict) -> dict:
    return event.get("malware") or {}


def get_source(event: dict) -> dict:
    return event.get("source") or {}


def get_destination(event: dict) -> dict:
    return event.get("destination") or {}



def build_malware_props(malware: dict) -> dict:
    mapping = {
        "family": "malware_family",
        "variant": "malware_variant",
    }
    return {dst: malware[src] for src, dst in mapping.items() if malware.get(src)}


def build_source_props(source: dict) -> dict:
    props = {}
    str_fields = {
        "ip": "source_ip",
        "isp": "source_isp",
        "country_iso": "country_iso",
        "city": "city",
    }
    for src_key, dst_key in str_fields.items():
        val = source.get(src_key)
        if val is not None and val != "":
            props[dst_key] = val

    for src_key, dst_key in (("port", "source_port"), ("asn", "source_asn")):
        val = source.get(src_key)
        if val is not None:
            props[dst_key] = val

    return props


def build_destination_props(destination: dict) -> dict:
    props = {}
    port = destination.get("port")
    if port is not None:
        props["destination_port"] = port
    dst_ip = destination.get("ip", "")
    if dst_ip:
        props["destination_ip"] = dst_ip
    return props



def parse_event(raw: dict) -> dict:
    malware = get_malware(raw)
    source = get_source(raw)
    destination = get_destination(raw)

    result: dict = {
        "id": raw.get("id", ""),
        "timestamp": raw.get("timestamp", ""),
        "event_type": raw.get("type", ""),
    }
    result.update(build_malware_props(malware))
    result.update(build_source_props(source))
    result.update(build_destination_props(destination))
    return result


def parse_file(data: list | dict) -> list[dict]:
    if isinstance(data, dict):
        events = data.get("events") or []
        if not events:
            logger.warning("parse_file: dict payload has no 'events' key — returning empty")
            return []
    else:
        events = list(data)
    return [parse_event(item) for item in events if isinstance(item, dict)]

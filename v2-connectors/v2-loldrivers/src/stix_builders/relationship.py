"""STIX2 Relationship builders for LOLDrivers."""

from __future__ import annotations

import uuid

from stix2 import Relationship

from config import STIX_NAMESPACE
from stix_builders.indicator import IOCGroupInfo, get_author


def create_based_on(indicator_id: str, observable_id: str, info: IOCGroupInfo) -> Relationship:
    """Create an Indicator 'based-on' Observable relationship."""
    rel_id = f"relationship--{uuid.uuid5(STIX_NAMESPACE, f'{indicator_id}:based-on:{observable_id}')}"
    return Relationship(
        id=rel_id,
        relationship_type="based-on",
        source_ref=indicator_id,
        target_ref=observable_id,
        created_by_ref=get_author().id,
        labels=["v2secure", "v2-driver", "v2-ioc", info.layer, info.group, info.tactic_id],
        allow_custom=True,
    )


def create_indicates(indicator_id: str, malware_id: str, info: IOCGroupInfo) -> Relationship:
    """Create an Indicator 'indicates' Malware relationship."""
    rel_id = f"relationship--{uuid.uuid5(STIX_NAMESPACE, f'{indicator_id}:indicates:{malware_id}')}"
    return Relationship(
        id=rel_id,
        relationship_type="indicates",
        source_ref=indicator_id,
        target_ref=malware_id,
        created_by_ref=get_author().id,
        labels=["v2secure", "v2-driver", "v2-ioc", info.layer, info.group, info.tactic_id],
        allow_custom=True,
    )

"""STIX2 Relationship builder for botnet IOCs."""

from __future__ import annotations

import uuid

from stix2 import IPv4Address, Indicator, Relationship

from stix_builder.indicator import STIX_NAMESPACE, get_author


def create_based_on(indicator: Indicator, observable: IPv4Address) -> Relationship:
    """Create a 'based-on' Relationship: Indicator → Observable."""
    det_id = "relationship--" + str(
        uuid.uuid5(STIX_NAMESPACE, f"based-on:{indicator.id}:{observable.id}")
    )
    return Relationship(
        id=det_id,
        relationship_type="based-on",
        source_ref=indicator.id,
        target_ref=observable.id,
        created_by_ref=get_author().id,
        confidence=100,
        allow_custom=True,
    )

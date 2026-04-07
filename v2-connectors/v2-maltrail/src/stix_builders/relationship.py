"""STIX2 Relationship builder for maltrail IOCs."""

from __future__ import annotations

import uuid

from stix2 import Relationship

from config import STIX_NAMESPACE
from stix_builders.indicator import get_author


def create_based_on(indicator, observable) -> Relationship:
    """Create a 'based-on' Relationship: Indicator → Observable."""
    rel_id = "relationship--" + str(
        uuid.uuid5(STIX_NAMESPACE, f"based-on:{indicator.id}:{observable.id}")
    )
    return Relationship(
        id=rel_id,
        relationship_type="based-on",
        source_ref=indicator.id,
        target_ref=observable.id,
        created_by_ref=get_author().id,
        confidence=100,
        labels=["v2 secure", "maltrail"],
        allow_custom=True,
    )

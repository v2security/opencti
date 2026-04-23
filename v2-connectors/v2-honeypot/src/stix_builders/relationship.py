"""STIX2 Relationship builder for V2Secure honeypot IOCs."""

from __future__ import annotations

import uuid

from stix2 import Relationship

from config import STIX_NAMESPACE
from parsers.honeypot import HoneypotRecord
from stix_builders.indicator import build_labels, get_author


def create_based_on(
    indicator_id: str, observable_id: str, record: HoneypotRecord
) -> Relationship:
    """Create an Indicator 'based-on' Observable relationship."""
    rel_id = "relationship--" + str(
        uuid.uuid5(
            STIX_NAMESPACE, f"based-on:{indicator_id}:{observable_id}"
        )
    )
    return Relationship(
        id=rel_id,
        relationship_type="based-on",
        source_ref=indicator_id,
        target_ref=observable_id,
        created_by_ref=get_author().id,
        confidence=100,
        labels=build_labels(record),
        allow_custom=True,
    )

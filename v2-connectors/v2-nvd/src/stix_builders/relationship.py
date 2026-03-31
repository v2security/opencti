"""STIX2 Relationship builder."""

import json

from stix2 import Relationship, Software, Vulnerability

from stix_builders.vulnerability import get_author


def create_relationship(
    software: Software,
    vuln: Vulnerability,
    hardware_cpes: list[str] | None = None,
) -> Relationship:
    """Create a STIX2 'has' Relationship: Software → Vulnerability.

    If *hardware_cpes* is provided, the CPE strings are stored in the
    relationship description so that the hardware context from NVD AND
    configurations is preserved.
    """
    kwargs: dict = {
        "relationship_type": "has",
        "source_ref": software.id,
        "target_ref": vuln.id,
        "created_by_ref": get_author().id,
        "confidence": 100,
        "allow_custom": True,
    }
    if hardware_cpes:
        kwargs["description"] = json.dumps(
            {"vulnerable_when_running_on": hardware_cpes},
            ensure_ascii=False,
        )
    return Relationship(**kwargs)

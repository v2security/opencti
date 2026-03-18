"""STIX2 Relationship builder."""

from stix2 import Relationship, Software, Vulnerability

from stix_builders.vulnerability import get_author


def create_relationship(software: Software, vuln: Vulnerability) -> Relationship:
    """Create a STIX2 'has' Relationship: Software → Vulnerability."""
    return Relationship(
        relationship_type="has",
        source_ref=software.id,
        target_ref=vuln.id,
        created_by_ref=get_author().id,
        confidence=100,
        allow_custom=True,
    )

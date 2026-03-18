"""STIX2 Relationship builder."""

from stix2 import Relationship, Software, Vulnerability


def create_relationship(software: Software, vuln: Vulnerability) -> Relationship:
    """Create a STIX2 'has' Relationship: Software → Vulnerability."""
    return Relationship(
        relationship_type="has",
        source_ref=software.id,
        target_ref=vuln.id,
        allow_custom=True,
    )

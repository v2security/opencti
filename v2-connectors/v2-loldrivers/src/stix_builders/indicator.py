"""STIX2 Indicator builder for LOLDrivers file hashes."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any

from stix2 import ExternalReference, Identity, Indicator

from config import LOLDRIVERS_URL, STIX_NAMESPACE
from parsers.driver import DriverEntry, DriverSample

# Author Identity for LOLDrivers
_AUTHOR = Identity(
    id="identity--" + str(uuid.uuid5(STIX_NAMESPACE, "LOLDrivers Project")),
    name="LOLDrivers Project",
    description="Living Off The Land Drivers — a curated list of Windows drivers used by adversaries.",
    identity_class="organization",
    contact_information="https://www.loldrivers.io/",
)


def get_author() -> Identity:
    """Return the LOLDrivers author Identity."""
    return _AUTHOR


def _build_hash_pattern(sample: DriverSample) -> str:
    """Build a STIX pattern from available file hashes.

    Uses SHA-256 as primary, falls back to SHA-1, then MD5.
    """
    parts = []
    if sample.sha256:
        parts.append(f"file:hashes.'SHA-256' = '{sample.sha256.lower()}'")
    if sample.sha1:
        parts.append(f"file:hashes.'SHA-1' = '{sample.sha1.lower()}'")
    if sample.md5:
        parts.append(f"file:hashes.'MD5' = '{sample.md5.lower()}'")
    if not parts:
        return ""
    # Use OR to match any hash
    return "[" + " OR ".join(parts) + "]"


def _category_to_label(category: str) -> str:
    """Map LOLDrivers category to a human-readable label."""
    if "malicious" in category:
        return "malicious-activity"
    return "anomalous-activity"


def create_indicator(
    driver: DriverEntry,
    sample: DriverSample,
) -> Indicator | None:
    """Create a STIX2 Indicator from a driver sample.

    Returns None if the sample has no usable hashes.
    """
    pattern = _build_hash_pattern(sample)
    if not pattern:
        return None

    # Deterministic ID based on driver ID + sample SHA256 (or SHA1/MD5)
    id_seed = f"{driver.driver_id}:{sample.sha256 or sample.sha1 or sample.md5}"
    indicator_id = f"indicator--{uuid.uuid5(STIX_NAMESPACE, id_seed)}"

    # Name: filename or first tag
    name = sample.filename or (driver.tags[0] if driver.tags else "Unknown Driver")
    description_parts = [f"LOLDrivers - {driver.category}"]
    if sample.description:
        description_parts.append(sample.description)
    if sample.company:
        description_parts.append(f"Company: {sample.company}")
    if sample.product:
        description_parts.append(f"Product: {sample.product}")
    if driver.usecase:
        description_parts.append(f"Use case: {driver.usecase}")
    if driver.command:
        description_parts.append(f"Command: {driver.command}")

    description = "\n".join(description_parts)

    # External references
    ext_refs = [
        ExternalReference(
            source_name="LOLDrivers",
            url=f"{LOLDRIVERS_URL}/drivers/{driver.driver_id}/",
            external_id=driver.driver_id,
            description=f"LOLDrivers entry for {name}",
        )
    ]
    for res_url in driver.resources:
        if res_url:
            ext_refs.append(
                ExternalReference(source_name="LOLDrivers Reference", url=res_url)
            )

    # Labels
    labels = ["v2secure", "v2-loldrivers", driver.category]
    if "malicious" in driver.category:
        labels.append("malicious-activity")
    else:
        labels.append("anomalous-activity")

    # Score: malicious = 80, vulnerable = 50
    score = 80 if "malicious" in driver.category else 50

    # Created timestamp
    try:
        created = datetime.strptime(driver.created, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    except (ValueError, TypeError):
        created = datetime.now(timezone.utc)

    kwargs: dict[str, Any] = {
        "id": indicator_id,
        "name": name,
        "description": description,
        "pattern": pattern,
        "pattern_type": "stix",
        "valid_from": created,
        "created": created,
        "modified": datetime.now(timezone.utc),
        "created_by_ref": _AUTHOR.id,
        "confidence": 90 if driver.verified else 60,
        "labels": labels,
        "external_references": ext_refs,
        "allow_custom": True,
        "x_opencti_score": score,
        "x_opencti_main_observable_type": "StixFile",
    }

    return Indicator(**kwargs)

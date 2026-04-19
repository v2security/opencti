"""Parser for LOLDrivers API response data."""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any

logger = logging.getLogger(__name__)


@dataclass
class DriverSample:
    """A single known vulnerable/malicious driver sample."""

    sha256: str = ""
    sha1: str = ""
    md5: str = ""
    filename: str = ""
    company: str = ""
    description: str = ""
    product: str = ""
    publisher: str = ""
    file_version: str = ""
    original_filename: str = ""
    imphash: str = ""
    authentihash_sha256: str = ""
    authentihash_sha1: str = ""
    authentihash_md5: str = ""
    loads_despite_hvci: str = ""


@dataclass
class DriverEntry:
    """Parsed driver entry with metadata and samples."""

    driver_id: str = ""
    tags: list[str] = field(default_factory=list)
    category: str = ""  # "vulnerable driver" or "Malicious"
    verified: bool = False
    author: str = ""
    created: str = ""
    mitre_id: str = ""  # e.g. "T1068"
    command: str = ""
    command_description: str = ""
    operating_system: str = ""
    privileges: str = ""
    usecase: str = ""
    resources: list[str] = field(default_factory=list)
    samples: list[DriverSample] = field(default_factory=list)


def parse_sample(raw: dict[str, Any]) -> DriverSample:
    """Parse a single KnownVulnerableSamples entry."""
    authentihash = raw.get("Authentihash") or {}
    return DriverSample(
        sha256=(raw.get("SHA256") or "").strip(),
        sha1=(raw.get("SHA1") or "").strip(),
        md5=(raw.get("MD5") or "").strip(),
        filename=(raw.get("Filename") or "").strip(),
        company=(raw.get("Company") or "").strip(),
        description=(raw.get("Description") or "").strip(),
        product=(raw.get("Product") or "").strip(),
        publisher=(raw.get("Publisher") or "").strip(),
        file_version=(raw.get("FileVersion") or "").strip(),
        original_filename=(raw.get("OriginalFilename") or "").strip(),
        imphash=(raw.get("Imphash") or "").strip(),
        authentihash_sha256=(authentihash.get("SHA256") or "").strip(),
        authentihash_sha1=(authentihash.get("SHA1") or "").strip(),
        authentihash_md5=(authentihash.get("MD5") or "").strip(),
        loads_despite_hvci=(raw.get("LoadsDespiteHVCI") or "").strip(),
    )


def parse_driver(raw: dict[str, Any]) -> DriverEntry:
    """Parse a single driver entry from the LOLDrivers API response."""
    commands = raw.get("Commands") or {}
    samples_raw = raw.get("KnownVulnerableSamples") or []

    samples = []
    for s in samples_raw:
        sample = parse_sample(s)
        # Only include samples that have at least one usable hash
        if sample.sha256 or sample.sha1 or sample.md5:
            samples.append(sample)

    verified_str = (raw.get("Verified") or "").upper()

    return DriverEntry(
        driver_id=raw.get("Id", ""),
        tags=raw.get("Tags") or [],
        category=(raw.get("Category") or "").lower().strip(),
        verified=verified_str == "TRUE",
        author=raw.get("Author") or "",
        created=raw.get("Created") or "",
        mitre_id=raw.get("MitreID") or "",
        command=commands.get("Command") or "",
        command_description=commands.get("Description") or "",
        operating_system=commands.get("OperatingSystem") or "",
        privileges=commands.get("Privileges") or "",
        usecase=commands.get("Usecase") or "",
        resources=raw.get("Resources") or [],
        samples=samples,
    )


def parse_all_drivers(
    raw_drivers: list[dict[str, Any]],
    import_malicious: bool = True,
    import_vulnerable: bool = True,
) -> list[DriverEntry]:
    """Parse and filter the full LOLDrivers API response.

    Args:
        raw_drivers: Raw JSON list from the API.
        import_malicious: Include drivers categorized as malicious.
        import_vulnerable: Include drivers categorized as vulnerable.

    Returns:
        List of parsed DriverEntry objects.
    """
    results = []
    for raw in raw_drivers:
        entry = parse_driver(raw)

        # Filter by category
        is_malicious = "malicious" in entry.category
        is_vulnerable = "vulnerable" in entry.category

        if is_malicious and not import_malicious:
            continue
        if is_vulnerable and not import_vulnerable:
            continue
        if not is_malicious and not is_vulnerable:
            # Unknown category — skip
            logger.warning("Unknown driver category: %s (id=%s)", entry.category, entry.driver_id)
            continue

        # Skip drivers with no usable samples
        if not entry.samples:
            logger.debug("Skipping driver %s — no samples with hashes", entry.driver_id)
            continue

        results.append(entry)

    logger.info(
        "Parsed %d drivers (%d with usable samples) from %d raw entries",
        len(results), len(results), len(raw_drivers),
    )
    return results

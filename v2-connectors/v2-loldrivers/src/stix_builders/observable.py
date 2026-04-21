"""STIX2 Observable (StixFile) builder for LOLDrivers samples."""

from __future__ import annotations

import uuid
from typing import Any

from stix2 import CustomObservable, File

from config import STIX_NAMESPACE
from parsers.driver import DriverEntry, DriverSample
from stix_builders.indicator import (
    IOCGroupInfo,
    _MALICIOUS_INFO,
    _VULNERABLE_INFO,
    get_author,
)


def create_observable(
    driver: DriverEntry,
    sample: DriverSample,
) -> File | None:
    """Create a STIX2 File observable from a driver sample.

    Returns None if the sample has no usable hashes.
    """
    hashes: dict[str, str] = {}
    if sample.sha256:
        hashes["SHA-256"] = sample.sha256.lower()
    if sample.sha1:
        hashes["SHA-1"] = sample.sha1.lower()
    if sample.md5:
        hashes["MD5"] = sample.md5.lower()

    if not hashes:
        return None

    # Deterministic ID
    id_seed = f"file:{sample.sha256 or sample.sha1 or sample.md5}"
    file_id = f"file--{uuid.uuid5(STIX_NAMESPACE, id_seed)}"

    name = sample.filename or (driver.tags[0] if driver.tags else "Unknown")

    info: IOCGroupInfo = _MALICIOUS_INFO if "malicious" in driver.category else _VULNERABLE_INFO

    kwargs: dict[str, Any] = {
        "id": file_id,
        "hashes": hashes,
        "name": name,
        "allow_custom": True,
        "x_opencti_description": f"LOLDrivers - {driver.category}: {name}",
        "labels": ["v2secure", "v2-driver", "v2-ioc", info.layer, info.group, info.tactic_id],
        "x_opencti_score": info.score,
        "x_opencti_created_by_ref": get_author().id,
    }

    return File(**kwargs)

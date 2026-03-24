"""STIX2 Software object builder."""

from typing import Any

from stix2 import Software

from parsers.cpe import parse_cpe
from utils import camel_to_snake


def create_software(cpe_match: dict) -> Software:
    """Create a STIX2 Software object from a CPE match entry."""
    cpe_string = cpe_match["criteria"]
    parsed = parse_cpe(cpe_string)

    vendor = parsed.get("vendor", "")
    product = parsed.get("product", "")
    version = parsed.get("version", "")

    # Build a readable name: "vendor product" or just "product"
    name = f"{vendor} {product}" if vendor and vendor != product else product

    kwargs: dict[str, Any] = {
        "name": name,
        "cpe": cpe_string,
        "allow_custom": True,
    }
    if vendor:
        kwargs["vendor"] = vendor
    if version:
        kwargs["version"] = version

    # Attach version range info as custom properties
    for range_key in (
        "versionStartIncluding",
        "versionStartExcluding",
        "versionEndIncluding",
        "versionEndExcluding",
    ):
        if range_key in cpe_match:
            kwargs[f"x_opencti_{camel_to_snake(range_key)}"] = cpe_match[range_key]

    return Software(**kwargs)

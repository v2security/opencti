# coding: utf-8

"""
Query IOC (Indicators of Compromise) from OpenCTI by IP, Domain, or Hash.
    Usage:
        from v2_get_ioc import query_ip, query_domain, query_hash

        result = query_ip("8.8.8.8")
        result = query_domain("evil.example.com")
        result = query_hash("ffe2ba06e19e6abaf1a8e6acb9d2c5dd836c38ca")

    Setup environment:

        # Create virtual environment
        python3 -m venv opencti-env
        source opencti-env/bin/activate
        pip install --upgrade pip
        pip install "pycti>=6,<7"
        
        # Or create conda environment
        conda create -n opencti-env python=3.12
        conda activate opencti-env
        pip install "pycti>=6,<7"

    Before running, configure API access in the script:
        api_url = "http://localhost:8080"
        api_token = "YOUR_OPENCTI_TOKEN"

    Run as CLI script:
        python v2_get_ioc.py ip 110.93.150.134
        python v2_get_ioc.py domain dialkwik.in
        python v2_get_ioc.py hash ffe2ba06e19e6abaf1a8e6acb9d2c5dd836c38ca
"""

import os
import re

from pycti import OpenCTIApiClient

# ---------------------------------------------------------------------------
# OpenCTI connection
# ---------------------------------------------------------------------------
API_URL = os.getenv("OPENCTI_API_URL", "http://163.223.58.7:8080")
API_TOKEN = os.getenv("OPENCTI_API_TOKEN", "ff91eda6-7317-4de3-96a3-5f8b7cc4a01f")
opencti_client = OpenCTIApiClient(API_URL, API_TOKEN)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _build_filter(key: str, values: list[str]) -> dict:
    """Build a standard FilterGroup dict for the OpenCTI API."""
    return {
        "mode": "and",
        "filters": [{"key": key, "values": values}],
        "filterGroups": [],
    }

# ---------------------------------------------------------------------------
# Public query functions
# ---------------------------------------------------------------------------
def query_ip(ip_address: str) -> dict | None:
    """
    Query an IP address observable (IPv4 or IPv6) from OpenCTI.

    Args:
        ip_address: The IP address to search for (e.g. "8.8.8.8" or "2001:db8::1").

    Returns:
        Observable dict if found, otherwise None.
    """
    ip_type = "IPv6-Addr" if ":" in ip_address else "IPv4-Addr"
    results = opencti_client.stix_cyber_observable.list(
        types=[ip_type],
        filters=_build_filter("value", [ip_address]),
        first=1,
    )
    return results[0] if results else None


def query_domain(domain_name: str) -> dict | None:
    """
    Query a Domain-Name observable from OpenCTI.

    Args:
        domain_name: The domain to search for (e.g. "evil.example.com").

    Returns:
        Observable dict if found, otherwise None.
    """
    results = opencti_client.stix_cyber_observable.list(
        types=["Domain-Name"],
        filters=_build_filter("value", [domain_name]),
        first=1,
    )
    return results[0] if results else None


def _detect_hash_type(hash_value: str) -> str:
    """Detect hash algorithm from the length of the value."""
    h = hash_value.strip().lower()
    if re.fullmatch(r"[a-f0-9]{32}", h):
        return "MD5"
    if re.fullmatch(r"[a-f0-9]{40}", h):
        return "SHA-1"
    if re.fullmatch(r"[a-f0-9]{64}", h):
        return "SHA-256"
    if re.fullmatch(r"[a-f0-9]{128}", h):
        return "SHA-512"
    raise ValueError(
        f"Cannot detect hash type for '{hash_value}'. "
        "Supported lengths: 32 (MD5), 40 (SHA-1), 64 (SHA-256), 128 (SHA-512)."
    )


def query_hash(hash_value: str) -> dict | None:
    """
    Query a file observable (StixFile / Artifact) from OpenCTI by hash.

    The hash type (MD5, SHA-1, SHA-256, SHA-512) is auto-detected from the
    length of the input string.

    Args:
        hash_value: The file hash to search for.

    Returns:
        Observable dict if found, otherwise None.
    """
    hash_type = _detect_hash_type(hash_value)
    filter_key = f"hashes.{hash_type}"
    results = opencti_client.stix_cyber_observable.list(
        types=["StixFile", "Artifact"],
        filters=_build_filter(filter_key, [hash_value.strip().lower()]),
        first=1,
    )
    return results[0] if results else None

# ---------------------------------------------------------------------------
# Main – quick demo / CLI usage
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import json
    import sys

    USAGE = (
        "Usage:\n"
        "  python v2_get_ioc.py ip     <ip_address>\n"
        "  python v2_get_ioc.py domain <domain_name>\n"
        "  python v2_get_ioc.py hash   <hash_value>\n"
    )

    if len(sys.argv) != 3:
        print(USAGE)
        sys.exit(1)

    ioc_type = sys.argv[1].lower()
    ioc_value = sys.argv[2]

    if ioc_type == "ip":
        result = query_ip(ioc_value)
    elif ioc_type == "domain":
        result = query_domain(ioc_value)
    elif ioc_type == "hash":
        result = query_hash(ioc_value)
    else:
        print(f"Unknown IOC type: '{ioc_type}'. Use ip, domain, or hash.")
        sys.exit(1)

    if result:
        print(json.dumps(result, indent=2, default=str))
    else:
        print(f"No result found for {ioc_type} = '{ioc_value}'")
        
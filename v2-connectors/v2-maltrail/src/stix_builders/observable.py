"""STIX2 Observable builder for maltrail IOCs."""

from __future__ import annotations

import uuid

from stix2 import DomainName, IPv4Address

from config import LABEL_SCORES, STIX_NAMESPACE
from stix_builders.indicator import get_author


def create_observable(
    value: str,
    label: str,
    ioc_type: str,
) -> IPv4Address | DomainName:
    """Create an IPv4-Addr or Domain-Name observable.

    Args:
        value: IOC value (IP address or domain name).
        label: Trail category (malware, malicious, suspicious).
        ioc_type: 'ipv4' or 'domain'.
    """
    score = LABEL_SCORES.get(label, 50)

    if ioc_type == "ipv4":
        observable_id = "ipv4-addr--" + str(uuid.uuid5(STIX_NAMESPACE, value))
        return IPv4Address(
            id=observable_id,
            value=value,
            created_by_ref=get_author().id,
            allow_custom=True,
            labels=["v2 secure", "maltrail"],
            x_opencti_score=score,
            x_opencti_description=f"Maltrail {label}: {value}",
        )
    else:
        observable_id = "domain-name--" + str(uuid.uuid5(STIX_NAMESPACE, value))
        return DomainName(
            id=observable_id,
            value=value,
            created_by_ref=get_author().id,
            allow_custom=True,
            labels=["v2 secure", "maltrail"],
            x_opencti_score=score,
            x_opencti_description=f"Maltrail {label}: {value}",
        )

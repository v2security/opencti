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
    file_tag: str = "",
) -> IPv4Address | DomainName:
    """Create an IPv4-Addr or Domain-Name observable.

    Args:
        value: IOC value (IP address or domain name).
        label: Trail category (malware, malicious, suspicious).
        ioc_type: 'ipv4' or 'domain'.
        file_tag: Semantic tag from the source filename (e.g. 'emotet', 'bad_wpad').
    """
    score = LABEL_SCORES.get(label, 50)
    obs_labels = ["v2 secure", "maltrail"]

    if file_tag:
        desc = f"Maltrail {label} ({file_tag}): {value}"
    else:
        desc = f"Maltrail {label}: {value}"

    if ioc_type == "ipv4":
        observable_id = "ipv4-addr--" + str(uuid.uuid5(STIX_NAMESPACE, value))
        return IPv4Address(
            id=observable_id,
            value=value,
            created_by_ref=get_author().id,
            allow_custom=True,
            labels=obs_labels,
            x_opencti_score=score,
            x_opencti_description=desc,
        )
    else:
        observable_id = "domain-name--" + str(uuid.uuid5(STIX_NAMESPACE, value))
        return DomainName(
            id=observable_id,
            value=value,
            created_by_ref=get_author().id,
            allow_custom=True,
            labels=obs_labels,
            x_opencti_score=score,
            x_opencti_description=desc,
        )

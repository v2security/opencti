"""STIX2 Observable builder for maltrail IOCs."""

from __future__ import annotations

import uuid

from stix2 import DomainName, IPv4Address

from config import STIX_NAMESPACE
from stix_builders.indicator import get_author
from trail.label_map import IOCGroupInfo


def create_observable(
    value: str,
    info: IOCGroupInfo,
    ioc_type: str,
    file_tag: str = "",
) -> IPv4Address | DomainName:
    """Create an IPv4-Addr or Domain-Name observable.

    Args:
        value: IOC value (IP address or domain name).
        info: IOCGroupInfo with layer, group, score, kill_chain.
        ioc_type: 'ipv4' or 'domain'.
        file_tag: Semantic tag from the source filename (e.g. 'emotet', 'bad_wpad').
    """
    obs_labels = ["v2secure", "v2-ioc", info.layer, info.group]

    if file_tag:
        desc = f"Maltrail {info.group} ({file_tag}): {value}"
    else:
        desc = f"Maltrail {info.group}: {value}"

    if ioc_type == "ipv4":
        observable_id = "ipv4-addr--" + str(uuid.uuid5(STIX_NAMESPACE, value))
        return IPv4Address(
            id=observable_id,
            value=value,
            created_by_ref=get_author().id,
            allow_custom=True,
            labels=obs_labels,
            x_opencti_score=info.score,
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
            x_opencti_score=info.score,
            x_opencti_description=desc,
        )

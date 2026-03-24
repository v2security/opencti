from __future__ import annotations

import json
import logging

from stix2 import Bundle

from stix_builder.indicator import create_indicator, get_author

logger = logging.getLogger(__name__)


def build_bundle(events: list[dict], verbose: bool = False) -> tuple[Bundle | None, int]:
    """Return (bundle, indicator_count). Bundle is None when no indicators were built."""
    objects = [get_author()]
    skipped = 0
    for event in events:
        if verbose:
            print(json.dumps(event, indent=2, ensure_ascii=False))
        indicator = create_indicator(event)
        if indicator is None:
            logger.warning("Skipped event %s — no source IP", event.get("id"))
            skipped += 1
            continue
        objects.append(indicator)

    built = len(objects) - 1  # first object is always the Identity author
    logger.info("Built %d indicator(s), skipped %d", built, skipped)

    if built == 0:
        return None, 0
    return Bundle(objects=objects, allow_custom=True), built

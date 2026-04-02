from __future__ import annotations

import json
import logging

from stix2 import Bundle

from stix_builder.indicator import create_indicator, get_author
from stix_builder.observable import create_observable
from stix_builder.relationship import create_based_on

logger = logging.getLogger(__name__)


def build_bundles(
    events: list[dict], verbose: bool = False
) -> tuple[Bundle | None, Bundle | None, int]:
    """Return (entities_bundle, relationships_bundle, indicator_count).

    Entities (Indicators + Observables) and Relationships are split into
    separate bundles so the caller can send entities first, avoiding race
    conditions when multiple workers process objects in parallel.
    """
    entities = [get_author()]
    relationships = []
    skipped = 0
    for event in events:
        if verbose:
            print(json.dumps(event, indent=2, ensure_ascii=False))
        indicator = create_indicator(event)
        if indicator is None:
            logger.warning("Skipped event %s — no source IP", event.get("id"))
            skipped += 1
            continue
        observable = create_observable(event)
        entities.append(indicator)
        entities.append(observable)
        relationships.append(create_based_on(indicator, observable))

    built = len(relationships)
    logger.info("Built %d indicator(s), skipped %d", built, skipped)

    if built == 0:
        return None, None, 0

    entities_bundle = Bundle(objects=entities, allow_custom=True)
    rels_bundle = Bundle(objects=relationships, allow_custom=True)
    return entities_bundle, rels_bundle, built

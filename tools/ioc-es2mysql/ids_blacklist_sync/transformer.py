"""ids_blacklist_sync.transformer — convert STIX 2.1 IP/Domain observables to ids_blacklist row dicts.

Each observable is mapped to a flat dict suitable for MySQL upsert, with
a GeoIP-derived ``country`` field added by the enrichment layer.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ids_blacklist_sync.enrichment import country_by_domain, country_by_ip
from util.logger import get_logger

log = get_logger(__name__)

_VERSION_FMT = "%Y%m%d%H%M%S"

# Maps STIX ``entity_type`` to the short type stored in MySQL.
_ENTITY_TYPE_MAP = {
    "IPv4-Addr": "ip",
    "IPv6-Addr": "ip",
    "Domain-Name": "domain",
}


def _source(obs: dict, fallback: str) -> str:
    """Extract the author/organisation name, falling back to *fallback*."""
    cb = obs.get("createdBy")
    if isinstance(cb, dict) and cb.get("name"):
        return str(cb["name"])
    return fallback


def _to_blacklist(obs: dict[str, Any], cfg: dict) -> dict | None:
    """Transform a single STIX observable into a blacklist row dict.

    The ``version`` column is derived from the entity's ``updated_at``
    field (converted to ``YYYYMMDDHHmmss``), so ``MAX(version)`` in MySQL
    always reflects the true data position in OpenCTI.

    Returns ``None`` (with a warning) when the observable cannot be mapped
    — e.g. unsupported ``entity_type`` or missing value.
    """
    stype = _ENTITY_TYPE_MAP.get(obs.get("entity_type", ""))
    if not stype:
        log.warning("Skipping unsupported entity_type '%s'.", obs.get("entity_type"))
        return None

    value = (obs.get("observable_value") or obs.get("value", "")).strip()
    if not value:
        log.warning("Skipping observable %s — no value.", obs.get("id"))
        return None

    # Derive version from entity's updated_at (ISO 8601 → YYYYMMDDHHmmss).
    updated_at = obs.get("updated_at", "")
    if updated_at:
        dt = datetime.fromisoformat(updated_at.replace("Z", "+00:00"))
        version = dt.strftime(_VERSION_FMT)
    else:
        # Fallback to wall-clock if updated_at is somehow missing.
        version = datetime.now(timezone.utc).strftime(_VERSION_FMT)
        log.warning("Observable %s has no updated_at — using wall-clock as version.", obs.get("id"))

    defaults = cfg.get("defaults", {})
    geoip_cfg = cfg.get("geoip", {})

    if stype == "ip":
        country = country_by_ip(value, geoip_cfg)
    elif stype == "domain":
        country = country_by_domain(value, geoip_cfg)
    else:
        country = "Unknown"

    # Parse created_at for cursor pagination (sort: [created_at, _id]).
    created_at_raw = obs.get("created_at", "")
    if created_at_raw:
        opencti_created_at = datetime.fromisoformat(
            created_at_raw.replace("Z", "+00:00")
        ).strftime("%Y-%m-%d %H:%M:%S")
    else:
        opencti_created_at = None

    return {
        "stype": stype,
        "value": value,
        "country": country,
        "source": _source(obs, defaults.get("source", "suspicious")),
        "srctype": defaults.get("srctype", "v2"),
        "type": defaults.get("type", "global"),
        "version": version,
        "opencti_id": obs.get("standard_id") or obs.get("id"),
        "opencti_created_at": opencti_created_at,
    }


def transform_ip_domain(observables: list[dict], cfg: dict) -> list[dict]:
    """Batch-transform IP/Domain observables into row dicts.

    Each row's ``version`` is derived from the entity's own ``updated_at``
    field so ``MAX(version)`` in MySQL reflects the true sync position.

    Observables that cannot be mapped are silently skipped (a warning is
    logged inside ``_to_blacklist``).
    """
    rows = [r for obs in observables if (r := _to_blacklist(obs, cfg)) is not None]
    log.info("Transformed %d/%d observables into blacklist rows.",
             len(rows), len(observables))
    return rows

"""util.client — OpenCTI API client and paginated query helpers.

Uses Relay cursor pagination (``withPagination=True``, ``after``):
  - Within a session the opaque ``endCursor`` gives exact page-to-page
    continuation with zero overlap or duplication.
  - On restart the cursor is lost; callers fall back to an
    ``updated_at >=`` filter, which is safe because writes are idempotent.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any, NamedTuple

from pycti import OpenCTIApiClient

from util.logger import get_logger

log = get_logger(__name__)


class PageResult(NamedTuple):
    """One page of observables together with Relay pagination metadata."""
    entities: list[dict]
    end_cursor: str | None
    has_next: bool


def create_client(opencti_cfg: dict) -> OpenCTIApiClient:
    """Create and return an ``OpenCTIApiClient`` from the *opencti* config block."""
    url = opencti_cfg["api_url"]
    log.info("Connecting to OpenCTI at %s …", url)
    client = OpenCTIApiClient(url, opencti_cfg["api_token"])
    log.info("OpenCTI client ready.")
    return client


def build_filters(min_score: int, min_confidence: int, since: datetime | None) -> dict[str, Any]:
    """Build an OpenCTI ``FilterGroup`` dict for observable queries.

    Filters applied:
      - ``x_opencti_score >= min_score``
      - ``confidence >= min_confidence``
      - ``updated_at >= since`` (only when *since* is not ``None``)
    """
    filters: list[dict[str, Any]] = [
        {"key": ["x_opencti_score"], "values": [str(min_score)], "operator": "gte"},
        {"key": ["confidence"], "values": [str(min_confidence)], "operator": "gte"},
    ]
    if since is not None:
        filters.append({
            "key": ["updated_at"],
            "values": [since.strftime("%Y-%m-%dT%H:%M:%S.000Z")],
            "operator": "gte",
        })
    return {"mode": "and", "filters": filters, "filterGroups": []}


def list_observables(
    client: OpenCTIApiClient,
    opencti_cfg: dict,
    types: list[str],
    since: datetime | None = None,
    after: str | None = None,
    max_items: int = 20,
) -> PageResult:
    """Fetch at most *max_items* observables ordered by ``updated_at ASC``.

    Parameters:
      *after*    — opaque Relay cursor from the previous page's ``endCursor``.
      *since*    — ``updated_at >=`` lower bound (used on the first query
                   after a restart, before a Relay cursor is available).

    When *after* is provided the actual start position is determined
    entirely by the Relay cursor; *since* is still sent as a filter but
    does not affect page boundaries.

    Returns a ``PageResult(entities, end_cursor, has_next)``.
    """
    min_score = int(opencti_cfg.get("min_score", 70))
    min_confidence = int(opencti_cfg.get("min_confidence", 70))
    fg = build_filters(min_score, min_confidence, since)
    log.debug("Querying OpenCTI: types=%s  since=%s  after=%s  max=%d",
              types, since, after is not None, max_items)
    result = client.stix_cyber_observable.list(
        types=types,
        filters=fg,
        first=max_items,
        after=after,
        orderBy="updated_at",
        orderMode="asc",
        getAll=False,
        withPagination=True,
    )
    entities = result.get("entities", [])
    pagination = result.get("pagination", {})
    end_cursor = pagination.get("endCursor")
    has_next = pagination.get("hasNextPage", False)
    log.info("Received %d observables (types=%s, max=%d, hasNext=%s).",
             len(entities), types, max_items, has_next)
    return PageResult(entities=entities, end_cursor=end_cursor, has_next=has_next)


def fetch_hash_iocs(
    client: OpenCTIApiClient,
    opencti_cfg: dict,
    since: datetime | None = None,
    after: str | None = None,
    max_items: int = 4,
) -> PageResult:
    """Fetch file-hash observables (``StixFile``, ``Artifact``)."""
    return list_observables(
        client, opencti_cfg,
        ["StixFile", "Artifact"],
        since, after, max_items,
    )


def fetch_ip_domain_iocs(
    client: OpenCTIApiClient,
    opencti_cfg: dict,
    since: datetime | None = None,
    after: str | None = None,
    max_items: int = 50,
) -> PageResult:
    """Fetch IP/Domain observables (``IPv4-Addr``, ``IPv6-Addr``, ``Domain-Name``)."""
    return list_observables(
        client, opencti_cfg,
        ["IPv4-Addr", "IPv6-Addr", "Domain-Name"],
        since, after, max_items,
    )

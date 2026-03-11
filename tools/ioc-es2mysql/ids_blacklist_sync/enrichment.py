"""ids_blacklist_sync.enrichment — GeoIP country lookup via a local MaxMind mmdb database.

All lookups are local (no external API call), so they are very fast and
do not need rate-limiting or quota tracking.
"""

from __future__ import annotations

import ipaddress
import socket

import geoip2.database

from util.logger import get_logger

log = get_logger(__name__)

_mmdb_reader: geoip2.database.Reader | None = None


def _get_reader(db_path: str) -> geoip2.database.Reader:
    """Return a singleton MaxMind reader, creating it on first call."""
    global _mmdb_reader
    if _mmdb_reader is None:
        log.info("Loading MaxMind database: %s", db_path)
        _mmdb_reader = geoip2.database.Reader(db_path)
    return _mmdb_reader


def _is_private(ip: str) -> bool:
    """Return ``True`` if *ip* is a private or reserved address."""
    try:
        return ipaddress.ip_address(ip).is_private
    except ValueError:
        return False


def _resolve_domain(domain: str) -> str | None:
    """Resolve *domain* to its first IPv4 address, or ``None`` on failure."""
    try:
        ip = socket.gethostbyname(domain)
        log.debug("Resolved %s → %s", domain, ip)
        return ip
    except socket.gaierror:
        log.debug("DNS resolution failed for %s.", domain)
        return None


def _ip_to_country(ip: str, db_path: str) -> str:
    """Look up the country name for *ip* via MaxMind.

    Returns ``"Local"`` for private/reserved addresses, ``"Unknown"`` on any
    lookup failure or missing data.
    """
    if not ip:
        return "Unknown"
    if _is_private(ip):
        return "Local"
    try:
        reader = _get_reader(db_path)
        resp = reader.country(ip)
        return resp.country.name or "Unknown"
    except Exception as exc:
        log.debug("MaxMind lookup failed for %s: %s", ip, exc)
        return "Unknown"


def country_by_ip(ip: str, geoip_cfg: dict) -> str:
    """Return the country name for an IP address.

    Private/reserved addresses → ``"Local"``, public → MaxMind lookup.
    """
    db_path = geoip_cfg.get("maxmind_db_path", "")
    if not db_path:
        log.warning("geoip.maxmind_db_path is not configured — returning 'Unknown'.")
        return "Unknown"
    return _ip_to_country(ip, db_path)


def country_by_domain(domain: str, geoip_cfg: dict) -> str:
    """Return the country name for a domain (DNS resolve → IP → MaxMind).

    Returns ``"Unknown"`` if the domain cannot be resolved.
    """
    db_path = geoip_cfg.get("maxmind_db_path", "")
    if not db_path:
        log.warning("geoip.maxmind_db_path is not configured — returning 'Unknown'.")
        return "Unknown"
    ip = _resolve_domain(domain)
    if ip is None:
        return "Unknown"
    return _ip_to_country(ip, db_path)

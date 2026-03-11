"""hashlist_sync.transformer — STIX 2.1 file-hash observable → hashlist row dict.

Transformation is pure data mapping — it does **not** call VirusTotal.
The scheduler is responsible for VT enrichment and rate-limit pacing;
it passes the VT result into ``transform_single`` / ``transform_batch``.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from util.logger import get_logger

log = get_logger(__name__)

_VERSION_FMT = "%Y%m%d%H%M%S"

# Default VT info when enrichment is skipped or unavailable.
VT_PASSTHROUGH: dict[str, str] = {"description": "unknown", "name": "unknown"}


# ── hash extraction helpers ──────────────────────────────────────────────


def all_hash_values(obs: dict) -> list[str]:
    """Return every hex-hash string present on *obs* (may be empty).

    pycti exposes hashes as either:
      - ``dict``  — ``{"MD5": "abc", "SHA-256": "def"}``
      - ``list``  — ``[{"algorithm": "MD5", "hash": "abc"}, …]``

    File-name-only observables (no hashes) return ``[]``.
    """
    hashes = obs.get("hashes")
    results: list[str] = []
    if isinstance(hashes, dict):
        for algo in ("MD5", "SHA-1", "SHA-256", "SHA-512"):
            v = hashes.get(algo)
            if v and v.strip():
                results.append(v.strip().lower())
    elif isinstance(hashes, list):
        for h in hashes:
            val = h.get("hash", "")
            if val and val.strip():
                results.append(val.strip().lower())
    return results


def best_hash_for_vt(hash_values: list[str]) -> str | None:
    """Pick the best hash to send to VirusTotal: SHA-256 > SHA-1 > MD5.

    Selection is based on string length:
      MD5 = 32, SHA-1 = 40, SHA-256 = 64, SHA-512 = 128.
    Returns ``None`` when *hash_values* is empty.
    """
    preferred_lengths = [64, 40, 32]
    by_len = {len(h): h for h in hash_values}
    for plen in preferred_lengths:
        if plen in by_len:
            return by_len[plen]
    return hash_values[0] if hash_values else None


# ── row building ─────────────────────────────────────────────────────────


def transform_single(
    obs: dict[str, Any],
    cfg: dict,
    vt_info: dict[str, str] | None = None,
) -> list[dict]:
    """Convert one STIX file-hash observable into a list of hashlist row dicts.

    Parameters:
      *vt_info* — pre-fetched ``{"description": …, "name": …}`` from VT.
                  If ``None``, ``VT_PASSTHROUGH`` is used (no VT call made).

    The ``version`` column is derived from the entity's ``updated_at``
    field so ``MAX(version)`` in MySQL reflects the true sync position.
    Each hash value in the observable produces one row.
    """
    hvs = all_hash_values(obs)
    if not hvs:
        log.debug("No hash in observable %s (%s) — skipped.",
                  obs.get("id"), obs.get("observable_value", ""))
        return []

    # Derive version from entity's updated_at (ISO 8601 → YYYYMMDDHHmmss).
    updated_at = obs.get("updated_at", "")
    if updated_at:
        dt = datetime.fromisoformat(updated_at.replace("Z", "+00:00"))
        version = dt.strftime(_VERSION_FMT)
    else:
        version = datetime.now(timezone.utc).strftime(_VERSION_FMT)
        log.warning("Observable %s has no updated_at — using wall-clock as version.", obs.get("id"))

    # Parse created_at for cursor pagination (sort: [created_at, _id]).
    created_at_raw = obs.get("created_at", "")
    if created_at_raw:
        opencti_created_at = datetime.fromisoformat(
            created_at_raw.replace("Z", "+00:00")
        ).strftime("%Y-%m-%d %H:%M:%S")
    else:
        opencti_created_at = None

    opencti_id = obs.get("standard_id") or obs.get("id")

    vt = vt_info if vt_info is not None else VT_PASSTHROUGH
    defaults = cfg.get("defaults", {})
    rows: list[dict] = []
    for hv in hvs:
        rows.append({
            "description": vt["description"],
            "name": vt["name"],
            "value": hv,
            "type": defaults.get("type", "global"),
            "version": version,
            "opencti_id": opencti_id,
            "opencti_created_at": opencti_created_at,
        })
    return rows


def transform_batch(
    observables: list[dict],
    cfg: dict,
    vt_results: list[dict[str, str] | None] | None = None,
) -> list[dict]:
    """Transform a list of observables into hashlist row dicts.

    *vt_results* is a parallel list of VT info dicts (one per observable).
    If ``None``, every observable gets ``VT_PASSTHROUGH``.

    Each row's ``version`` is derived from its entity's own ``updated_at``
    so ``MAX(version)`` in MySQL reflects the true sync position.
    """
    if vt_results is None:
        vt_results = [None] * len(observables)

    rows: list[dict] = []
    for obs, vt in zip(observables, vt_results):
        rows.extend(transform_single(obs, cfg, vt))

    log.info("Transformed %d rows from %d observables.",
             len(rows), len(observables))
    return rows

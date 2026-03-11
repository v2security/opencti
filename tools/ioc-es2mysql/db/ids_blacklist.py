"""db.ids_blacklist — upsert IP/Domain rows into the ``ids_blacklist`` table."""

from __future__ import annotations

from typing import Sequence

from db.conn import MySQLPool
from util.logger import get_logger

log = get_logger(__name__)

_UPSERT_SQL = """
INSERT INTO ids_blacklist (stype, value, country, source, srctype, `type`, version, opencti_id, opencti_created_at)
VALUES (%(stype)s, %(value)s, %(country)s, %(source)s, %(srctype)s, %(type)s, %(version)s, %(opencti_id)s, %(opencti_created_at)s)
ON DUPLICATE KEY UPDATE
    country            = VALUES(country),
    source             = VALUES(source),
    version            = VALUES(version),
    opencti_id         = VALUES(opencti_id),
    opencti_created_at = VALUES(opencti_created_at)
"""


def upsert_blacklist(pool: MySQLPool, rows: Sequence[dict]) -> int:
    """Insert or update blacklist rows and return the total affected row count.

    Each dict must contain keys:
    ``stype``, ``value``, ``country``, ``source``, ``srctype``, ``type``, ``version``,
    ``opencti_id``, ``opencti_created_at``.
    """
    if not rows:
        return 0
    affected = 0
    with pool.cursor() as cur:
        for r in rows:
            cur.execute(_UPSERT_SQL, r)
            affected += cur.rowcount
    log.info("Upserted %d rows (%d input).", affected, len(rows))
    return affected

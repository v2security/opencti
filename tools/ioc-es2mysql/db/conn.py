"""db.conn — MySQL connection pool and shared helpers.

Provides ``MySQLPool`` (a thin wrapper around ``mysql.connector.pooling``)
and ``get_last_version`` which reads the sync resume point from a table.
"""

from __future__ import annotations

from contextlib import contextmanager
from typing import Generator

import mysql.connector
from mysql.connector import pooling

from util.logger import get_logger

log = get_logger(__name__)


# ── connection pool ─────────────────────────────────────────────────────

class MySQLPool:
    """Manage a shared MySQL connection pool.

    Initialised from the ``mysql`` block of ``config.yaml``.
    """

    def __init__(self, mysql_cfg: dict) -> None:
        self._cfg = mysql_cfg
        self._pool: pooling.MySQLConnectionPool | None = None

    def connect(self) -> None:
        """Create the underlying connection pool and verify connectivity."""
        c = self._cfg
        log.info(
            "Connecting to MySQL %s@%s:%s/%s (pool_size=%d) …",
            c["user"], c["host"], c["port"], c["database"], c.get("pool_size", 5),
        )
        self._pool = pooling.MySQLConnectionPool(
            pool_name="ioc_sync",
            pool_size=int(c.get("pool_size", 5)),
            pool_reset_session=True,
            host=str(c["host"]),
            port=int(c["port"]),
            user=str(c["user"]),
            password=str(c["password"]),
            database=str(c["database"]),
            charset="utf8mb4",
            collation="utf8mb4_unicode_ci",
            autocommit=False,
        )
        # Verify the pool works by borrowing and returning one connection.
        with self.cursor() as _cur:
            log.info("MySQL connection pool ready.")

    def close(self) -> None:
        """Release the pool (best-effort — ``mysql.connector`` pools do not
        expose an explicit shutdown method)."""
        log.info("MySQL pool released.")

    @contextmanager
    def connection(self) -> Generator[mysql.connector.MySQLConnection, None, None]:
        """Borrow a connection from the pool (returned automatically)."""
        if self._pool is None:
            raise RuntimeError("MySQLPool.connect() has not been called yet.")
        cnx = self._pool.get_connection()
        try:
            yield cnx
        finally:
            cnx.close()

    @contextmanager
    def cursor(self, *, dictionary: bool = True):
        """Borrow a connection, yield a cursor, commit on success / rollback on error."""
        with self.connection() as cnx:
            cur = cnx.cursor(dictionary=dictionary)
            try:
                yield cur
                cnx.commit()
            except Exception:
                cnx.rollback()
                raise
            finally:
                cur.close()


# ── resume helper ───────────────────────────────────────────────────────

# Only these table names are allowed to prevent SQL-injection via the
# unparameterisable table identifier.
_ALLOWED_TABLES = {"ids_blacklist", "hashlist"}


def get_last_version(pool: MySQLPool, table: str) -> str | None:
    """Return the newest ``version`` value from *table*, or ``None`` if empty.

    The ``version`` column stores ``YYYYMMDDHHmmss`` strings so ``MAX()``
    gives the chronologically latest entry via lexicographic comparison.
    """
    if table not in _ALLOWED_TABLES:
        raise ValueError(f"Unknown table: {table!r}")

    with pool.cursor() as cur:
        cur.execute(f"SELECT MAX(version) AS v FROM {table}")
        v = (cur.fetchone() or {}).get("v")

    if not v:
        log.info("Table %s is empty — no previous sync position.", table)
        return None
    log.info("Last version in %s: %s.", table, v)
    return v

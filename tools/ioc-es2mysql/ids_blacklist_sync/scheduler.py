"""ids_blacklist_sync.scheduler — drain loop for IP/Domain blacklist with GeoIP enrichment.

Pagination uses Relay cursors (backed by Elasticsearch ``search_after``):
  - Within a session the opaque ``endCursor`` is carried forward, giving
    exact page-to-page continuation with zero overlap or duplication.
  - On process restart the cursor is lost; the scheduler falls back to an
    ``updated_at >=`` filter derived from MySQL, which is safe because
    every write is an idempotent upsert.
"""

from __future__ import annotations

import signal
import time
from datetime import datetime, timezone

from db.conn import MySQLPool, get_last_version
from db.ids_blacklist import upsert_blacklist
from util.client import fetch_ip_domain_iocs
from util.client import create_client
from util.logger import get_logger

from ids_blacklist_sync.transformer import transform_ip_domain

log = get_logger(__name__)

_VERSION_FMT = "%Y%m%d%H%M%S"


def _version_to_dt(v: str) -> datetime:
    """Parse a ``YYYYMMDDHHmmss`` version string into a UTC datetime."""
    return datetime.strptime(v, _VERSION_FMT).replace(tzinfo=timezone.utc)


class BlacklistScheduler:
    """Continuously drain IP/Domain observables from OpenCTI into MySQL.

    Each observable is enriched with a GeoIP country via a local MaxMind
    mmdb lookup (very fast, no external API call).
    """

    def __init__(self, cfg: dict) -> None:
        self._cfg = cfg
        self._sched = cfg.get("scheduler", {})
        self._running = False
        self._pool = MySQLPool(cfg["mysql"])
        self._octi = None
        # Opaque Relay cursor — valid only within the current session.
        self._after: str | None = None
        # Fallback ``updated_at`` lower bound — used for the very first
        # query after startup, before a Relay cursor is available.
        self._since: datetime | None = None

    # ── lifecycle ────────────────────────────────────────────────────────

    def _setup(self) -> None:
        """Connect to MySQL and OpenCTI, resolve the initial sync position."""
        self._pool.connect()
        self._octi = create_client(self._cfg["opencti"])
        self._since = self._resolve_initial_cursor()
        self._after = None  # no Relay cursor yet; first query uses ``since``

        log.info(
            "Scheduler ready — batch=%s  sleep=%ss  idle=%ss  since=%s",
            self._sched.get("geoip_batch_size", 50),
            self._sched.get("geoip_sleep_seconds", 5),
            self._sched.get("idle_sleep_seconds", 60),
            self._since.strftime(_VERSION_FMT) if self._since else "EPOCH",
        )

    def _teardown(self) -> None:
        """Release the MySQL connection pool."""
        self._pool.close()
        log.info("Scheduler shut down.")

    def _resolve_initial_cursor(self) -> datetime | None:
        """Pick the latest starting point from config and MySQL.

        Returns ``None`` when neither source provides a timestamp,
        meaning the sync will start from the earliest available data.
        """
        cfg_start = self._sched.get("time_start_sync", "")
        db_version = get_last_version(self._pool, "ids_blacklist")

        cursor_cfg = _version_to_dt(cfg_start) if cfg_start else None
        cursor_db = _version_to_dt(db_version) if db_version else None

        candidates = [c for c in (cursor_cfg, cursor_db) if c is not None]
        if not candidates:
            log.info("No previous sync position found — starting from epoch.")
            return None

        chosen = max(candidates)
        log.info(
            "Resuming from %s  (config=%s, mysql=%s)",
            chosen.strftime(_VERSION_FMT),
            cursor_cfg.strftime(_VERSION_FMT) if cursor_cfg else "-",
            cursor_db.strftime(_VERSION_FMT) if cursor_db else "-",
        )
        return chosen

    # ── helpers ──────────────────────────────────────────────────────────

    def _interruptible_sleep(self, seconds: int) -> None:
        """Sleep up to *seconds*, waking early if a stop signal arrives."""
        for _ in range(seconds):
            if not self._running:
                break
            time.sleep(1)

    # ── single batch ────────────────────────────────────────────────────

    def _sync_batch(self) -> int:
        """Fetch one page from OpenCTI, enrich with GeoIP, and upsert to MySQL.

        First call after startup uses the ``updated_at`` filter (``self._since``).
        Subsequent calls use the Relay ``endCursor`` for exact continuation.

        Returns the number of observables processed (0 = no more data).
        """
        max_items = int(self._sched.get("geoip_batch_size", 50))

        page = fetch_ip_domain_iocs(
            self._octi, self._cfg["opencti"],
            since=self._since, after=self._after, max_items=max_items,
        )
        if not page.entities:
            return 0

        rows = transform_ip_domain(page.entities, self._cfg)
        affected = upsert_blacklist(self._pool, rows)

        # Carry the Relay cursor forward for the next page.
        self._after = page.end_cursor
        # Once we have a Relay cursor the ``since`` filter is unnecessary.
        if self._after:
            self._since = None

        log.info("Fetched %d  upserted %d  hasNext=%s",
                 len(page.entities), affected, page.has_next)
        return len(page.entities)

    # ── drain loop ──────────────────────────────────────────────────────

    def _drain(self) -> int:
        """Process all available pages: fetch → enrich → upsert → sleep → repeat.

        Stops when a page returns zero entities or a stop signal is received.
        """
        sleep_sec = int(self._sched.get("geoip_sleep_seconds", 5))
        total = 0
        log.info("Drain started  batch=%s  sleep=%ds",
                 self._sched.get("geoip_batch_size", 50), sleep_sec)

        while self._running:
            n = self._sync_batch()
            total += n
            if n == 0:
                break
            if self._running:
                log.info("Sleeping %ds before next batch …", sleep_sec)
                self._interruptible_sleep(sleep_sec)

        log.info("Drain finished — %d records processed.", total)
        return total

    # ── main loops ──────────────────────────────────────────────────────

    def run_forever(self) -> None:
        """Run drain loops continuously until a SIGINT/SIGTERM is received.

        After each drain completes (no more data), the scheduler sleeps
        for ``idle_sleep_seconds`` before checking for new data.
        """
        self._setup()
        self._running = True
        idle_sleep = int(self._sched.get("idle_sleep_seconds", 60))

        def _stop(signum, _frame):
            log.info("Received signal %d — shutting down …", signum)
            self._running = False

        signal.signal(signal.SIGINT, _stop)
        signal.signal(signal.SIGTERM, _stop)

        log.info("Running (Ctrl+C to stop) …")
        try:
            while self._running:
                try:
                    n = self._drain()
                except Exception:
                    log.exception("Drain failed — will retry after idle sleep.")
                    n = 0

                if not self._running:
                    break

                if n > 0:
                    continue

                log.info("No new data — idle sleep %ds …", idle_sleep)
                self._interruptible_sleep(idle_sleep)
        finally:
            self._teardown()

    def run_once(self) -> None:
        """Execute a single drain then exit."""
        self._setup()
        self._running = True
        try:
            self._drain()
        finally:
            self._teardown()

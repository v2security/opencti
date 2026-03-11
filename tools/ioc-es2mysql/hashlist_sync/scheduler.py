"""hashlist_sync.scheduler — Hashlist drain loop (Hash + VirusTotal).

Rate-limit enforcement
~~~~~~~~~~~~~~~~~~~~~~
VirusTotal free-tier imposes three limits:

  ====  ===========  ===========
  Tier  Limit        Config key
  ====  ===========  ===========
  min   4 req/min    ``vt_rate_limit``
  day   500 req/day  ``vt_daily_quota``
  month 15 500/month ``vt_monthly_quota``
  ====  ===========  ===========

Per-minute pacing is handled by ``VtEnricher`` (sleeps between calls).
Daily and monthly counters live here so the scheduler can stop early
when a quota is exhausted.

Relay cursor pagination
~~~~~~~~~~~~~~~~~~~~~~~
  - Within a session: ``endCursor`` (ES search_after) — exact, no overlap.
  - On restart: fallback ``updated_at >=`` filter from MySQL — upsert is
    idempotent so duplicates are harmless.
"""

from __future__ import annotations

import signal
import time
from datetime import datetime, timezone, date

from hashlist_sync.enrichment import VtEnricher, VT_PASSTHROUGH
from hashlist_sync.transformer import (
    all_hash_values,
    best_hash_for_vt,
    transform_batch,
)
from db.conn import MySQLPool, get_last_version
from db.hashlist import upsert_hashlist
from util.client import create_client, fetch_hash_iocs
from util.logger import get_logger

log = get_logger(__name__)

_VERSION_FMT = "%Y%m%d%H%M%S"


def _version_to_dt(v: str) -> datetime:
    """Parse a *YYYYMMDDHHmmss* version string into a UTC datetime."""
    return datetime.strptime(v, _VERSION_FMT).replace(tzinfo=timezone.utc)


class HashlistScheduler:
    """Drain loop for file-hash observables with VirusTotal enrichment.

    Processes observables one at a time within each batch so that the
    per-minute throttle (``VtEnricher``) can insert pauses between
    successive API calls.  The scheduler additionally tracks daily and
    monthly quota counters and stops enrichment when either is exhausted.
    """

    def __init__(self, cfg: dict) -> None:
        self._cfg = cfg
        self._sched = cfg.get("scheduler", {})
        self._running = False
        self._pool = MySQLPool(cfg["mysql"])
        self._octi = None

        # Relay cursor — valid within a session, None on startup.
        self._after: str | None = None
        # updated_at lower-bound — used on restart before a cursor exists.
        self._since: datetime | None = None

        # ── VT quota config ──────────────────────────────────────────────
        self._vt_rate_limit = int(self._sched.get("vt_rate_limit", 4))
        self._vt_daily_quota = int(self._sched.get("vt_daily_quota", 500))
        self._vt_monthly_quota = int(self._sched.get("vt_monthly_quota", 15500))

        # ── VT quota counters ────────────────────────────────────────────
        self._vt_calls_today = 0
        self._vt_calls_month = 0
        self._vt_quota_date: date | None = None    # tracks current day
        self._vt_quota_month: int | None = None     # tracks current month (1-12)

        # VtEnricher (created in _setup once config is fully resolved).
        self._vt: VtEnricher | None = None

    # ── lifecycle ────────────────────────────────────────────────────────

    def _setup(self) -> None:
        """Connect to MySQL, OpenCTI; initialise VT enricher and counters."""
        self._pool.connect()
        self._octi = create_client(self._cfg["opencti"])
        self._since = self._resolve_initial_cursor()
        self._after = None

        # Initialise VtEnricher with per-minute throttle.
        self._vt = VtEnricher(
            self._cfg.get("virustotal", {}),
            rate_limit=self._vt_rate_limit,
        )

        today = date.today()
        self._vt_quota_date = today
        self._vt_quota_month = today.month
        self._vt_calls_today = 0
        self._vt_calls_month = 0

        log.info(
            "HashlistScheduler ready — batch=%d  rate=%d/min  "
            "daily_quota=%d  monthly_quota=%d  idle=%ds  since=%s",
            int(self._sched.get("vt_batch_size", 4)),
            self._vt_rate_limit,
            self._vt_daily_quota,
            self._vt_monthly_quota,
            int(self._sched.get("idle_sleep_seconds", 60)),
            self._since.strftime(_VERSION_FMT) if self._since else "EPOCH",
        )

    def _teardown(self) -> None:
        self._pool.close()
        log.info("HashlistScheduler shut down.")

    def _resolve_initial_cursor(self) -> datetime | None:
        """Determine the ``updated_at`` lower bound for the first query.

        Uses the later of config ``time_start_sync`` and the MySQL
        ``MAX(version)`` so that a restart never re-processes old data.
        """
        cfg_start = self._sched.get("time_start_sync", "")
        db_version = get_last_version(self._pool, "hashlist")

        cursor_cfg = _version_to_dt(cfg_start) if cfg_start else None
        cursor_db = _version_to_dt(db_version) if db_version else None

        candidates = [c for c in (cursor_cfg, cursor_db) if c is not None]
        if not candidates:
            log.info("No cursor found — full sync from epoch.")
            return None

        chosen = max(candidates)
        log.info(
            "Initial cursor: %s  (config=%s, db=%s).",
            chosen.strftime(_VERSION_FMT),
            cursor_cfg.strftime(_VERSION_FMT) if cursor_cfg else "-",
            cursor_db.strftime(_VERSION_FMT) if cursor_db else "-",
        )
        return chosen

    # ── VT quota tracking ───────────────────────────────────────────────

    def _reset_quotas_if_needed(self) -> None:
        """Reset daily and/or monthly counters when the calendar rolls over."""
        today = date.today()

        if self._vt_quota_date != today:
            log.info("VT daily counter reset — new day %s (yesterday used %d/%d).",
                     today, self._vt_calls_today, self._vt_daily_quota)
            self._vt_calls_today = 0
            self._vt_quota_date = today

        if self._vt_quota_month != today.month:
            log.info("VT monthly counter reset — new month %d (last month used %d/%d).",
                     today.month, self._vt_calls_month, self._vt_monthly_quota)
            self._vt_calls_month = 0
            self._vt_quota_month = today.month

    def _vt_quota_ok(self) -> bool:
        """Return ``True`` if both daily and monthly quotas have headroom."""
        self._reset_quotas_if_needed()
        return (self._vt_calls_today < self._vt_daily_quota
                and self._vt_calls_month < self._vt_monthly_quota)

    def _record_vt_call(self) -> None:
        """Increment daily and monthly counters after one VT API call."""
        self._vt_calls_today += 1
        self._vt_calls_month += 1
        log.debug("VT usage — today %d/%d  month %d/%d.",
                  self._vt_calls_today, self._vt_daily_quota,
                  self._vt_calls_month, self._vt_monthly_quota)

    # ── helpers ──────────────────────────────────────────────────────────

    def _interruptible_sleep(self, seconds: int) -> None:
        """Sleep in 1-second increments so shutdown signals are responsive."""
        for _ in range(seconds):
            if not self._running:
                break
            time.sleep(1)

    # ── single batch ────────────────────────────────────────────────────

    def _sync_batch(self) -> int:
        """Fetch one page → enrich each observable via VT → upsert.

        The method iterates over every observable in the page and calls
        VT **one at a time**.  ``VtEnricher.enrich()`` sleeps internally
        to honour the per-minute rate limit.  If the daily or monthly
        quota is exhausted mid-batch the remaining observables still get
        rows (with ``VT_PASSTHROUGH``) so data is never lost — only
        enrichment is skipped.

        Returns the number of observables fetched (0 = no more data).
        """
        max_items = int(self._sched.get("vt_batch_size", 4))

        page = fetch_hash_iocs(
            self._octi, self._cfg["opencti"],
            since=self._since, after=self._after, max_items=max_items,
        )
        if not page.entities:
            return 0

        # Enrich each observable individually, respecting quotas.
        vt_results: list[dict[str, str] | None] = []
        vt_calls = 0
        for obs in page.entities:
            hvs = all_hash_values(obs)
            best = best_hash_for_vt(hvs)

            if best and self._vt and self._vt.enabled and self._vt_quota_ok():
                vt_info = self._vt.enrich(best)
                self._record_vt_call()
                vt_calls += 1
            else:
                vt_info = VT_PASSTHROUGH

            vt_results.append(vt_info)

        rows = transform_batch(page.entities, self._cfg, vt_results)
        affected = upsert_hashlist(self._pool, rows)

        # Advance Relay cursor for the next page.
        self._after = page.end_cursor
        if self._after:
            self._since = None

        log.info(
            "▸ hashlist: fetched=%d  upserted=%d  vt_calls=%d  "
            "today=%d/%d  month=%d/%d  hasNext=%s",
            len(page.entities), affected, vt_calls,
            self._vt_calls_today, self._vt_daily_quota,
            self._vt_calls_month, self._vt_monthly_quota,
            page.has_next,
        )
        return len(page.entities)

    # ── drain loop ──────────────────────────────────────────────────────

    def _drain(self) -> int:
        """Drain all available hashes: fetch → enrich → upsert → repeat.

        Stops when:
          - No more data (query returns 0 entities).
          - VT daily **or** monthly quota exhausted.
          - Shutdown signal received.
        """
        total = 0
        log.info(
            "── Hashlist drain start (batch=%d, rate=%d/min, "
            "vt_day=%d/%d, vt_month=%d/%d) ──",
            int(self._sched.get("vt_batch_size", 4)),
            self._vt_rate_limit,
            self._vt_calls_today, self._vt_daily_quota,
            self._vt_calls_month, self._vt_monthly_quota,
        )

        while self._running:
            if not self._vt_quota_ok():
                log.warning(
                    "VT quota exhausted (day %d/%d, month %d/%d) "
                    "— pausing enrichment.",
                    self._vt_calls_today, self._vt_daily_quota,
                    self._vt_calls_month, self._vt_monthly_quota,
                )
                break

            n = self._sync_batch()
            total += n
            if n == 0:
                break

        log.info(
            "── Hashlist drain done — total %d observables  "
            "vt_day=%d/%d  vt_month=%d/%d ──",
            total,
            self._vt_calls_today, self._vt_daily_quota,
            self._vt_calls_month, self._vt_monthly_quota,
        )
        return total

    # ── main loops ──────────────────────────────────────────────────────

    def run_forever(self) -> None:
        """Run continuously until a shutdown signal is received.

        When the VT quota is exhausted the loop enters idle sleep and
        re-checks periodically; counters auto-reset at midnight / month
        boundary.
        """
        self._setup()
        self._running = True
        idle_sleep = int(self._sched.get("idle_sleep_seconds", 60))

        def _stop(signum, _frame):
            log.info("Signal %d received — stopping …", signum)
            self._running = False

        signal.signal(signal.SIGINT, _stop)
        signal.signal(signal.SIGTERM, _stop)

        log.info("Hashlist loop started …")
        try:
            while self._running:
                try:
                    n = self._drain()
                except Exception:
                    log.exception("Hashlist drain failed — retrying after idle sleep.")
                    n = 0

                if not self._running:
                    break

                if n > 0 and self._vt_quota_ok():
                    continue

                log.info(
                    "Idle sleep %ds … (vt_day=%d/%d, vt_month=%d/%d)",
                    idle_sleep,
                    self._vt_calls_today, self._vt_daily_quota,
                    self._vt_calls_month, self._vt_monthly_quota,
                )
                self._interruptible_sleep(idle_sleep)
        finally:
            self._teardown()

    def run_once(self) -> None:
        """Execute a single drain pass then stop."""
        self._setup()
        self._running = True
        try:
            self._drain()
        finally:
            self._teardown()

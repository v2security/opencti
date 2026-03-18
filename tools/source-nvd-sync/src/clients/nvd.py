"""
NVD REST API 2.0 client with rate limiting.

Rate limits (per NVD docs):
    - With API key : 50 requests / 30 seconds  → ~0.6 s between requests
    - Without API key: 5 requests / 30 seconds → ~6 s between requests

The client transparently paginates through results and respects the
rolling window rate limit by sleeping between API calls.
"""

import json
import logging
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from typing import Any, Iterator

logger = logging.getLogger(__name__)

# NVD API page size (maximum allowed)
_RESULTS_PER_PAGE = 2000

# Rate limiting: seconds between requests
_DELAY_WITH_KEY = 0.6  # 50 req / 30 s
_DELAY_WITHOUT_KEY = 6.0  # 5 req / 30 s


class NvdApiClient:
    """Paginated, rate-limited NVD CVE API 2.0 client."""

    def __init__(self, base_url: str, api_key: str = "", request_timeout: int = 30):
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.request_timeout = request_timeout
        self._delay = _DELAY_WITH_KEY if api_key else _DELAY_WITHOUT_KEY
        self._last_request_time = 0.0

    # ------------------------------------------------------------------
    # Public helpers for building date windows
    # ------------------------------------------------------------------

    @staticmethod
    def date_windows(
        start: datetime, end: datetime, max_days: int = 120
    ) -> list[tuple[datetime, datetime]]:
        """Split a date range into windows of at most *max_days* days."""
        windows: list[tuple[datetime, datetime]] = []
        current = start
        while current < end:
            window_end = min(current + timedelta(days=max_days), end)
            windows.append((current, window_end))
            current = window_end
        return windows

    # ------------------------------------------------------------------
    # Core fetch
    # ------------------------------------------------------------------

    def fetch_cves(
        self,
        last_mod_start: datetime | None = None,
        last_mod_end: datetime | None = None,
        pub_start: datetime | None = None,
        pub_end: datetime | None = None,
    ) -> Iterator[dict]:
        """Yield individual CVE dicts, paginating automatically.

        Uses lastModStartDate/lastModEndDate for incremental sync, or
        pubStartDate/pubEndDate for historical pulls.
        """
        params: dict[str, str] = {"resultsPerPage": str(_RESULTS_PER_PAGE)}
        if last_mod_start and last_mod_end:
            params["lastModStartDate"] = _iso(last_mod_start)
            params["lastModEndDate"] = _iso(last_mod_end)
        elif pub_start and pub_end:
            params["pubStartDate"] = _iso(pub_start)
            params["pubEndDate"] = _iso(pub_end)

        start_index = 0
        total = None
        while total is None or start_index < total:
            params["startIndex"] = str(start_index)
            data = self._get(params)
            if data is None:
                break
            total = data.get("totalResults", 0)
            vulns = data.get("vulnerabilities", [])
            if not vulns:
                break
            for entry in vulns:
                cve = entry.get("cve")
                if cve:
                    yield cve
            start_index += len(vulns)
            logger.info("NVD API: fetched %d / %d CVEs", start_index, total)

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _get(self, params: dict[str, str]) -> dict[str, Any] | None:
        """Execute a single GET request with rate limiting and retries."""
        self._respect_rate_limit()

        url = f"{self.base_url}?{urllib.parse.urlencode(params)}"
        req = urllib.request.Request(url)
        if self.api_key:
            req.add_header("apiKey", self.api_key)

        for attempt in range(3):
            try:
                with urllib.request.urlopen(req, timeout=self.request_timeout) as resp:
                    self._last_request_time = time.monotonic()
                    return json.loads(resp.read().decode())
            except urllib.error.HTTPError as exc:
                if exc.code == 403:
                    wait = (attempt + 1) * 30
                    logger.warning(
                        "NVD API 403 (rate limited), retrying in %ds …", wait
                    )
                    time.sleep(wait)
                    continue
                if exc.code == 503:
                    wait = (attempt + 1) * 10
                    logger.warning(
                        "NVD API 503 (service unavailable), retrying in %ds …", wait
                    )
                    time.sleep(wait)
                    continue
                logger.error("NVD API HTTP %d: %s", exc.code, exc.reason)
                return None
            except Exception:
                logger.exception("NVD API request failed (attempt %d)", attempt + 1)
                if attempt < 2:
                    time.sleep(5)
        return None

    def _respect_rate_limit(self) -> None:
        """Sleep if necessary to respect the rolling rate limit."""
        elapsed = time.monotonic() - self._last_request_time
        if elapsed < self._delay:
            time.sleep(self._delay - elapsed)


def _iso(dt: datetime) -> str:
    """Format a datetime as ISO 8601 for the NVD API."""
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000")

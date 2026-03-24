"""
EPSS API client with rate limiting.

Fetches Exploit Prediction Scoring System scores from api.first.org.

Rate limits (per FIRST API docs):
    - Public (no auth): 1000 requests / minute  → ~0.06 s between requests
    - Conservative default: 0.1 s between requests (~600 req/min)

The FIRST EPSS API supports batch queries: up to 100 CVEs per request
via comma-separated ``cve`` parameter.  This client batches CVE IDs
accordingly and respects rate limits between batch calls.

API docs: https://www.first.org/epss/api
"""

from __future__ import annotations

import json
import logging
import time
import urllib.error
import urllib.request

logger = logging.getLogger(__name__)

# Rate limiting: seconds between requests (conservative default)
_DEFAULT_DELAY = 0.1  # 1000 req/min allowed, we use ~600 req/min


class EpssApiClient:
    """Rate-limited EPSS API client."""

    def __init__(
        self,
        api_url: str = "https://api.first.org/data/v1/epss",
        batch_size: int = 30,
        request_timeout: int = 30,
        request_delay: float = _DEFAULT_DELAY,
    ):
        self.api_url = api_url.rstrip("/")
        self.batch_size = min(batch_size, 100)
        self.request_timeout = request_timeout
        self._delay = request_delay
        self._last_request_time = 0.0

    def fetch_scores(self, cve_ids: list[str]) -> dict[str, dict[str, str]]:
        """Fetch EPSS data for a list of CVE IDs.

        Returns ``{cve_id: {"epss": "0.004…", "percentile": "0.616…"}}``.
        Returns empty dict if *cve_ids* is empty.
        """
        if not cve_ids:
            return {}

        logger.info("Fetching EPSS scores for %d CVEs …", len(cve_ids))
        results: dict[str, dict[str, str]] = {}

        for i in range(0, len(cve_ids), self.batch_size):
            batch = cve_ids[i : i + self.batch_size]
            results.update(self._fetch_batch(batch))

        logger.info(
            "EPSS: received scores for %d / %d CVEs", len(results), len(cve_ids)
        )
        return results

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _fetch_batch(self, cve_ids: list[str]) -> dict[str, dict[str, str]]:
        """Fetch a single batch (≤ batch_size) from the EPSS API."""
        self._respect_rate_limit()

        cve_param = ",".join(cve_ids)
        url = f"{self.api_url}?cve={cve_param}"

        for attempt in range(3):
            try:
                req = urllib.request.Request(url)
                with urllib.request.urlopen(req, timeout=self.request_timeout) as resp:
                    self._last_request_time = time.monotonic()
                    body = json.loads(resp.read().decode())
                break
            except urllib.error.HTTPError as exc:
                if exc.code == 429:
                    wait = (attempt + 1) * 10
                    logger.warning(
                        "EPSS API 429 (rate limited), retrying in %ds …", wait
                    )
                    time.sleep(wait)
                    continue
                logger.error("EPSS API HTTP %d: %s", exc.code, exc.reason)
                return {}
            except Exception:
                logger.exception(
                    "EPSS API request failed (attempt %d)", attempt + 1
                )
                if attempt < 2:
                    time.sleep(2)
                    continue
                return {}

        results: dict[str, dict[str, str]] = {}
        for entry in body.get("data", []):
            cve_id = entry.get("cve")
            if cve_id:
                results[cve_id] = {
                    "epss": entry.get("epss", ""),
                    "percentile": entry.get("percentile", ""),
                }
        return results

    def _respect_rate_limit(self) -> None:
        """Sleep if necessary to respect the FIRST API rate limit."""
        elapsed = time.monotonic() - self._last_request_time
        if elapsed < self._delay:
            time.sleep(self._delay - elapsed)

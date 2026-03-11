"""hashlist_sync.enrichment — VirusTotal API enrichment with rate-limit throttle.

Free-tier limits (configurable via ``config.yaml``):
  * **Per-minute**: 4 lookups / min  → ``vt_rate_limit``
  * **Daily**:      500 lookups / day → ``vt_daily_quota``
  * **Monthly**:    15 500 lookups / month → ``vt_monthly_quota``

``VtEnricher`` enforces the per-minute cap by sleeping ``60 / rate_limit``
seconds between successive API calls.  Daily and monthly quota tracking
is the scheduler's responsibility (it reads ``.vt_calls_today`` /
``.vt_calls_month`` after each call).
"""

from __future__ import annotations

import time

import requests

from util.logger import get_logger

log = get_logger(__name__)

VT_PASSTHROUGH: dict[str, str] = {"description": "unknown", "name": "unknown"}

_VT_URL_DEFAULT = "https://www.virustotal.com/api/v3/files/{hash}"
_VT_TIMEOUT_DEFAULT = 10


class VtEnricher:
    """Stateful VirusTotal enricher with per-call rate-limit throttle.

    The throttle ensures at most ``rate_limit`` calls per 60-second
    window by sleeping a computed interval between consecutive calls.
    """

    def __init__(self, vt_cfg: dict, rate_limit: int = 4) -> None:
        self._enabled: bool = bool(vt_cfg.get("enabled"))
        self._api_key: str = vt_cfg.get("api_key", "")
        self._url: str = vt_cfg.get("url", _VT_URL_DEFAULT)
        self._timeout: int = int(vt_cfg.get("timeout", _VT_TIMEOUT_DEFAULT))

        # Per-minute throttle — minimum seconds between two consecutive calls.
        self._rate_limit = max(1, rate_limit)
        self._min_interval: float = 60.0 / self._rate_limit
        self._last_call_ts: float = 0.0  # monotonic timestamp of last API call

    # ── public API ───────────────────────────────────────────────────────

    @property
    def enabled(self) -> bool:
        """``True`` when VT enrichment is configured and active."""
        return self._enabled and bool(self._api_key)

    def enrich(self, file_hash: str) -> dict[str, str]:
        """Look up *file_hash* on VirusTotal and return description/name.

        Automatically sleeps to respect the per-minute rate limit before
        making the HTTP request.  Returns ``VT_PASSTHROUGH`` on error or
        when enrichment is disabled.
        """
        if not self.enabled:
            return VT_PASSTHROUGH

        self._throttle()
        return self._call_api(file_hash)

    # ── internals ────────────────────────────────────────────────────────

    def _throttle(self) -> None:
        """Sleep until the minimum inter-call interval has elapsed."""
        now = time.monotonic()
        elapsed = now - self._last_call_ts
        if elapsed < self._min_interval:
            wait = self._min_interval - elapsed
            log.debug("VT throttle — sleeping %.1fs (interval=%.1fs).",
                      wait, self._min_interval)
            time.sleep(wait)

    def _call_api(self, file_hash: str) -> dict[str, str]:
        """Execute one VT API GET and parse the result."""
        self._last_call_ts = time.monotonic()
        try:
            resp = requests.get(
                self._url.format(hash=file_hash),
                headers={"x-apikey": self._api_key},
                timeout=self._timeout,
            )
            resp.raise_for_status()
            attrs = resp.json().get("data", {}).get("attributes", {})

            # Prefer the first malicious/suspicious vendor result.
            for vendor, result in attrs.get("last_analysis_results", {}).items():
                if result.get("category") in ("malicious", "suspicious"):
                    return {"description": vendor,
                            "name": result.get("result", "unknown")}

            # Fallback to the community threat label.
            label = (attrs
                     .get("popular_threat_classification", {})
                     .get("suggested_threat_label", "unknown"))
            return {"description": "VirusTotal", "name": label}

        except Exception as exc:
            log.warning("VT API failed for %s: %s", file_hash, exc)
            return VT_PASSTHROUGH

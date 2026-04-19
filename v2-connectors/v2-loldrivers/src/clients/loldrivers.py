"""HTTP client for the LOLDrivers API."""

from __future__ import annotations

import logging
from typing import Any

import requests

logger = logging.getLogger(__name__)


class LolDriversApiClient:
    """Fetches driver data from the LOLDrivers public JSON API.

    No authentication required — the API is fully public.
    """

    def __init__(self, api_url: str, request_timeout: int = 60):
        self.api_url = api_url
        self.request_timeout = request_timeout
        self._session = requests.Session()
        self._session.headers.update(
            {"Accept": "application/json", "User-Agent": "OpenCTI-LOLDrivers-Connector/1.0"}
        )

    def fetch_drivers(self) -> list[dict[str, Any]]:
        """Fetch the complete driver list from the LOLDrivers API.

        Returns:
            List of driver dicts, each containing Id, Tags, Category,
            KnownVulnerableSamples, etc.
        """
        logger.info("Fetching drivers from %s", self.api_url)
        resp = self._session.get(self.api_url, timeout=self.request_timeout)
        resp.raise_for_status()
        drivers = resp.json()
        logger.info("Fetched %d drivers from LOLDrivers API", len(drivers))
        return drivers

"""
NVD CVE Connector for OpenCTI.

Fetches CVE data from the NVD REST API 2.0, enriches with EPSS scores
(optional), builds STIX2 bundles with Vulnerability + Software + Relationship
objects, and syncs them into OpenCTI.

Supports two operating modes:
  - Incremental updates (maintain_data): syncs CVEs modified since last run.
  - Historical import (pull_history): pulls all CVEs from a start year.
"""

from __future__ import annotations

import logging
import os
import sys
from datetime import datetime, timedelta, timezone
from typing import Any

import yaml
from pycti import OpenCTIConnectorHelper
from stix2 import Bundle

# Ensure src/ is on path so bare imports work from any working directory
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from clients.epss import EpssApiClient
from clients.nvd import NvdApiClient
from config import ConnectorConfig
from parsers.cpe import extract_vulnerable_cpes
from parsers.cve import get_description
from stix_builders.relationship import create_relationship
from stix_builders.software import create_software
from stix_builders.vulnerability import create_vulnerability, get_author

logger = logging.getLogger(__name__)


class NvdCveConnector:
    """OpenCTI EXTERNAL_IMPORT connector for NVD CVE data."""

    def __init__(self):
        config_path = os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "..", "config.yml"
        )
        raw_config: dict = {}
        if os.path.isfile(config_path):
            with open(config_path, encoding="utf-8") as f:
                raw_config = yaml.safe_load(f) or {}

        self.cfg = ConnectorConfig(raw_config)
        self.helper = OpenCTIConnectorHelper(raw_config)

        # API clients
        self.nvd = NvdApiClient(
            base_url=self.cfg.nvd_base_url,
            api_key=self.cfg.nvd_api_key,
            request_timeout=self.cfg.nvd_request_timeout,
        )
        self.epss = EpssApiClient(
            api_url=self.cfg.epss_api_url,
            batch_size=self.cfg.epss_batch_size,
            request_timeout=self.cfg.epss_request_timeout,
            request_delay=self.cfg.epss_request_delay,
        ) if self.cfg.epss_enabled else None

    # ------------------------------------------------------------------
    # Main processing loop — called by the scheduler
    # ------------------------------------------------------------------

    def process_data(self) -> None:
        """Run one sync cycle."""
        self.helper.connector_logger.info("NVD CVE connector: starting sync cycle")

        try:
            state = self.helper.get_state() or {}
            now = datetime.now(timezone.utc)

            if self.cfg.nvd_pull_history:
                self._pull_history(state, now)
            elif self.cfg.nvd_maintain_data:
                self._maintain_data(state, now)
            else:
                self.helper.connector_logger.warning(
                    "Neither maintain_data nor pull_history is enabled; nothing to do"
                )
        except Exception:
            self.helper.connector_logger.exception("Sync cycle failed")

    # ------------------------------------------------------------------
    # Sync strategies
    # ------------------------------------------------------------------

    def _maintain_data(self, state: dict, now: datetime) -> None:
        """Incremental sync: fetch CVEs modified since last run."""
        last_run_iso = state.get("last_run")
        if last_run_iso:
            start = datetime.fromisoformat(last_run_iso)
        else:
            # First run — default to 24 hours ago
            start = now - timedelta(hours=24)

        self.helper.connector_logger.info(
            "Incremental sync: %s → %s",
            start.isoformat(),
            now.isoformat(),
        )

        windows = NvdApiClient.date_windows(
            start, now, max_days=self.cfg.nvd_max_date_range
        )
        total_synced = 0
        for win_start, win_end in windows:
            count = self._sync_window(
                last_mod_start=win_start, last_mod_end=win_end
            )
            total_synced += count

        self.helper.set_state({"last_run": now.isoformat()})
        self.helper.connector_logger.info(
            "Incremental sync complete: %d CVEs synced", total_synced
        )

    def _pull_history(self, state: dict, now: datetime) -> None:
        """Historical import: pull CVEs from start year to present."""
        min_year = max(self.cfg.nvd_history_start_year, 1999)
        start = datetime(min_year, 1, 1, tzinfo=timezone.utc)

        # Resume from where we stopped if applicable
        history_cursor = state.get("history_cursor")
        if history_cursor:
            start = datetime.fromisoformat(history_cursor)

        self.helper.connector_logger.info(
            "Historical import: %s → %s",
            start.isoformat(),
            now.isoformat(),
        )

        windows = NvdApiClient.date_windows(
            start, now, max_days=self.cfg.nvd_max_date_range
        )
        total_synced = 0
        for win_start, win_end in windows:
            count = self._sync_window(pub_start=win_start, pub_end=win_end)
            total_synced += count
            # Save progress so we can resume on failure
            self.helper.set_state(
                {
                    "history_cursor": win_end.isoformat(),
                    "last_run": now.isoformat(),
                }
            )

        self.helper.set_state(
            {
                "history_cursor": now.isoformat(),
                "last_run": now.isoformat(),
            }
        )
        self.helper.connector_logger.info(
            "Historical import complete: %d CVEs synced", total_synced
        )

    # ------------------------------------------------------------------
    # Core sync logic
    # ------------------------------------------------------------------

    def _sync_window(self, **api_kwargs) -> int:
        """Fetch CVEs for one date window, enrich, build bundles, send."""
        cve_list = list(self.nvd.fetch_cves(**api_kwargs))
        if not cve_list:
            return 0

        # Batch EPSS enrichment
        epss_map: dict = {}
        if self.epss:
            cve_ids = [c["id"] for c in cve_list if c.get("id")]
            epss_map = self.epss.fetch_scores(cve_ids)

        work_id = self.helper.api.work.initiate_work(
            self.helper.connect_id,
            f"NVD CVE sync ({len(cve_list)} CVEs)",
        )

        synced = 0
        for cve_data in cve_list:
            cve_id = cve_data.get("id", "unknown")
            try:
                bundle = self._build_bundle(cve_data, epss_map.get(cve_id))
                if bundle is None:
                    continue
                self.helper.send_stix2_bundle(
                    bundle.serialize(),
                    work_id=work_id,
                    update=True,
                )
                synced += 1
            except Exception:
                self.helper.connector_logger.exception(
                    "Failed to sync %s", cve_id
                )

        message = f"Synced {synced}/{len(cve_list)} CVEs"
        self.helper.api.work.to_processed(work_id, message)
        self.helper.connector_logger.info(message)
        return synced

    def _build_bundle(
        self, cve_data: dict, epss_data: dict | None
    ) -> Bundle | None:
        """Build a STIX2 Bundle from a single CVE entry."""
        if not get_description(cve_data):
            self.helper.connector_logger.debug(
                "Skipping %s — no description", cve_data.get("id")
            )
            return None

        vuln = create_vulnerability(cve_data, epss_data=epss_data)
        objects: list[Any] = [get_author(), vuln]

        for cpe_match in extract_vulnerable_cpes(cve_data):
            sw = create_software(cpe_match)
            rel = create_relationship(
                sw, vuln, hardware_cpes=cpe_match.get("_hardware_cpes")
            )
            objects.extend([sw, rel])

        return Bundle(objects=objects, allow_custom=True)

    # ------------------------------------------------------------------
    # Entry point
    # ------------------------------------------------------------------

    def start(self) -> None:
        """Start the connector with ISO 8601 scheduling."""
        self.helper.schedule_iso(
            message_callback=self.process_data,
            duration_period=self.cfg.connector_duration_period,
        )

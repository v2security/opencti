"""
NVD CVE Connector for OpenCTI.

Fetches CVE data from the NVD REST API 2.0, enriches with EPSS scores
(optional), builds STIX2 bundles with Vulnerability + Software + Relationship
objects, and syncs them into OpenCTI.

Supports two operating modes:
  - Incremental updates (maintain_data): syncs CVEs modified since last run.
  - Historical import (pull_history): pulls all CVEs from a start year.

Uses two-phase bundle sending to prevent race conditions:
  Phase 1: Send all entity bundles (Vulnerability + Software)
  Phase 2: Wait relationship_delay seconds, then send relationship bundles
"""

from __future__ import annotations

import logging
import os
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import yaml
from dotenv import load_dotenv
from pycti import OpenCTIConnectorHelper
from stix2 import Bundle

# Load .env from v2-connectors/ (walk up from this file's location)
def _find_and_load_env() -> None:
    current = Path(__file__).resolve().parent
    for _ in range(6):
        env_file = current / ".env"
        if env_file.is_file():
            load_dotenv(env_file, override=False)
            return
        current = current.parent

_find_and_load_env()

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
            self.helper.connector_logger.error("Sync cycle failed")

        self.helper.connector_logger.info(
            f"Sync cycle finished. Waiting {self.cfg.connector_duration_period} before next run "
            f"(duration_period={self.cfg.connector_duration_period})"
        )

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
            f"Incremental sync: {start.isoformat()} → {now.isoformat()}"
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
            f"Incremental sync complete: {total_synced} CVEs synced"
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
            f"Historical import: {start.isoformat()} → {now.isoformat()}"
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
            f"Historical import complete: {total_synced} CVEs synced"
        )

    # ------------------------------------------------------------------
    # Core sync logic
    # ------------------------------------------------------------------

    def _sync_window(self, **api_kwargs) -> int:
        """Fetch CVEs for one date window, enrich, build bundles, send.

        Uses two-phase sending to avoid race conditions:
          Phase 1: Send all entity bundles (Vulnerability + Software)
          Phase 2: Wait relationship_delay, then send relationship bundles
        """
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

        # --- Phase 1: Build and send entity bundles, collect relationships ---
        synced = 0
        pending_rels: list[str] = []  # serialized relationship bundles

        for cve_data in cve_list:
            cve_id = cve_data.get("id", "unknown")
            try:
                entities_bundle, rels_bundle = self._build_bundles(
                    cve_data, epss_map.get(cve_id)
                )
                if entities_bundle is None:
                    continue
                self.helper.send_stix2_bundle(
                    entities_bundle.serialize(),
                    work_id=work_id,
                    update=True,
                )
                if rels_bundle is not None:
                    pending_rels.append(rels_bundle.serialize())
                synced += 1
            except Exception:
                self.helper.connector_logger.error(
                    f"Failed to sync {cve_id}"
                )

        # --- Phase 2: Wait for entities to be processed, then send relationships ---
        if pending_rels:
            delay = self.cfg.relationship_delay
            self.helper.connector_logger.info(
                f"Phase 1 done: {synced} entity bundles sent. "
                f"Waiting {delay}s before sending {len(pending_rels)} relationship bundles…"
            )
            time.sleep(delay)

            self.helper.connector_logger.info(
                f"Phase 2: sending {len(pending_rels)} relationship bundles"
            )
            for rels_data in pending_rels:
                self.helper.send_stix2_bundle(
                    rels_data,
                    work_id=work_id,
                    update=True,
                )

        message = f"Synced {synced}/{len(cve_list)} CVEs"
        self.helper.api.work.to_processed(work_id, message)
        self.helper.connector_logger.info(message)
        return synced

    def _build_bundles(
        self, cve_data: dict, epss_data: dict | None
    ) -> tuple[Bundle | None, Bundle | None]:
        """Build STIX2 Bundles from a single CVE entry.

        Returns two bundles to avoid race conditions when workers process
        objects in parallel:
          1. Entities bundle (Vulnerability + Software)
          2. Relationships bundle (Software → Vulnerability)

        The caller must send the entities bundle first so that referenced
        objects exist (or are queued) before the relationships arrive.
        """
        if not get_description(cve_data):
            self.helper.connector_logger.debug(
                f"Skipping {cve_data.get('id')} — no description"
            )
            return None, None

        vuln = create_vulnerability(cve_data, epss_data=epss_data)
        entities: list[Any] = [get_author(), vuln]
        relationships: list[Any] = []

        for cpe_match in extract_vulnerable_cpes(cve_data):
            sw = create_software(cpe_match)
            rel = create_relationship(
                sw, vuln, hardware_cpes=cpe_match.get("_hardware_cpes")
            )
            entities.append(sw)
            relationships.append(rel)

        # Tag vulnerability as having relationships if any software was linked
        if relationships:
            vuln = vuln.new_version(labels=list(vuln.get("labels", [])) + ["has-relationships"])
            entities[1] = vuln

        entities_bundle = Bundle(objects=entities, allow_custom=True)
        rels_bundle = (
            Bundle(objects=relationships, allow_custom=True)
            if relationships
            else None
        )
        return entities_bundle, rels_bundle

    # ------------------------------------------------------------------
    # Entry point
    # ------------------------------------------------------------------

    def start(self) -> None:
        """Start the connector with ISO 8601 scheduling."""
        self.helper.schedule_iso(
            message_callback=self.process_data,
            duration_period=self.cfg.connector_duration_period,
        )

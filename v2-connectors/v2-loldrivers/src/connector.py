"""
LOLDrivers Connector for OpenCTI.

Fetches vulnerable and malicious Windows driver data from the LOLDrivers
public API (https://www.loldrivers.io/api/drivers.json), builds STIX2
bundles, and syncs them into OpenCTI.

No authentication required — the LOLDrivers API is fully public.

STIX mapping:
  - Each driver → Malware object (represents the driver threat)
  - Each sample (hash) → Indicator (STIX pattern with file hashes)
  - Each sample → File observable (SHA-256, SHA-1, MD5)
  - Indicator 'based-on' Observable
  - Indicator 'indicates' Malware

Uses two-phase bundle sending to prevent race conditions:
  Phase 1: Send all entity bundles (Malware + Indicator + Observable)
  Phase 2: Wait relationship_delay seconds, then send relationship bundles
"""

from __future__ import annotations

import logging
import os
import sys
import time
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

from clients.loldrivers import LolDriversApiClient
from config import ConnectorConfig
from parsers.driver import DriverEntry, parse_all_drivers
from stix_builders.indicator import create_indicator, get_author
from stix_builders.malware import create_malware
from stix_builders.observable import create_observable
from stix_builders.relationship import create_based_on, create_indicates

logger = logging.getLogger(__name__)


class LolDriversConnector:
    """OpenCTI EXTERNAL_IMPORT connector for LOLDrivers data."""

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

        # API client
        self.client = LolDriversApiClient(
            api_url=self.cfg.loldrivers_api_url,
            request_timeout=self.cfg.loldrivers_request_timeout,
        )

    # ------------------------------------------------------------------
    # Main processing loop — called by the scheduler
    # ------------------------------------------------------------------

    def process_data(self) -> None:
        """Run one sync cycle."""
        self.helper.connector_logger.info("LOLDrivers connector: starting sync cycle")

        try:
            self._run_sync()
        except Exception:
            self.helper.connector_logger.error(
                "Sync cycle failed", exc_info=True
            )

        self.helper.connector_logger.info(
            f"Sync cycle finished. Waiting {self.cfg.connector_duration_period} "
            f"before next run."
        )

    # ------------------------------------------------------------------
    # Sync pipeline
    # ------------------------------------------------------------------

    def _run_sync(self) -> None:
        # Step 1: Fetch drivers from API
        self.helper.connector_logger.info("Step 1/3: Fetching drivers from LOLDrivers API")
        raw_drivers = self.client.fetch_drivers()

        # Step 2: Parse and filter
        self.helper.connector_logger.info("Step 2/3: Parsing and filtering drivers")
        drivers = parse_all_drivers(
            raw_drivers,
            import_malicious=self.cfg.loldrivers_import_malicious,
            import_vulnerable=self.cfg.loldrivers_import_vulnerable,
        )

        if not drivers:
            self.helper.connector_logger.info("No drivers to import after filtering")
            return

        # Step 3: Build STIX bundles and push to OpenCTI
        self.helper.connector_logger.info(
            f"Step 3/3: Building and pushing STIX bundles for {len(drivers)} drivers"
        )
        self._push_drivers(drivers)

    # ------------------------------------------------------------------
    # STIX bundle creation and push
    # ------------------------------------------------------------------

    def _push_drivers(self, drivers: list[DriverEntry]) -> None:
        """Build STIX bundles and send to OpenCTI in batches.

        Uses two-phase sending:
          Phase 1: Send all entity bundles, collect relationship bundles
          Phase 2: Wait relationship_delay, then send relationship bundles
        """
        bundle_size = self.cfg.loldrivers_bundle_size
        total_synced = 0

        work_id = self.helper.api.work.initiate_work(
            self.helper.connect_id,
            f"LOLDrivers sync ({len(drivers)} drivers)",
        )

        # --- Phase 1: Send entity bundles, collect relationships ---
        pending_rels: list[str] = []

        for i in range(0, len(drivers), bundle_size):
            batch = drivers[i : i + bundle_size]
            entities_bundle, rels_bundle, count = self._build_bundles(batch)

            if entities_bundle is None:
                continue

            self.helper.send_stix2_bundle(
                entities_bundle.serialize(),
                work_id=work_id,
                update=True,
            )
            if rels_bundle is not None:
                pending_rels.append(rels_bundle.serialize())
            total_synced += count

        # --- Phase 2: Wait, then send relationship bundles ---
        if pending_rels:
            delay = self.cfg.relationship_delay
            self.helper.connector_logger.info(
                f"Phase 1 done: {total_synced} entities sent. "
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

        message = f"Synced {total_synced} driver samples from {len(drivers)} LOLDrivers entries"
        self.helper.api.work.to_processed(work_id, message)
        self.helper.connector_logger.info(message)

    def _build_bundles(
        self, batch: list[DriverEntry]
    ) -> tuple[Bundle | None, Bundle | None, int]:
        """Build STIX2 Bundles from a batch of driver entries.

        Returns (entities_bundle, relationships_bundle, sample_count).
        """
        entities: list[Any] = [get_author()]
        relationships: list[Any] = []
        sample_count = 0

        for driver in batch:
            try:
                # Create Malware object for the driver
                malware = create_malware(driver)
                entities.append(malware)

                for sample in driver.samples:
                    # Create Indicator (hash-based detection pattern)
                    if self.cfg.loldrivers_create_indicators:
                        indicator = create_indicator(driver, sample)
                        if indicator:
                            entities.append(indicator)

                            # Indicator 'indicates' Malware
                            rel_indicates = create_indicates(indicator.id, malware.id)
                            relationships.append(rel_indicates)

                    # Create Observable (StixFile)
                    if self.cfg.loldrivers_create_observables:
                        observable = create_observable(driver, sample)
                        if observable:
                            entities.append(observable)

                            # Indicator 'based-on' Observable
                            if self.cfg.loldrivers_create_indicators and indicator:
                                rel_based_on = create_based_on(indicator.id, observable.id)
                                relationships.append(rel_based_on)

                    sample_count += 1

            except Exception:
                self.helper.connector_logger.warning(
                    f"Failed to build STIX for driver {driver.driver_id}",
                    exc_info=True,
                )

        if sample_count == 0:
            return None, None, 0

        entities_bundle = Bundle(objects=entities, allow_custom=True)
        rels_bundle = (
            Bundle(objects=relationships, allow_custom=True) if relationships else None
        )
        return entities_bundle, rels_bundle, sample_count

    # ------------------------------------------------------------------
    # Entry point
    # ------------------------------------------------------------------

    def start(self) -> None:
        """Start the connector with ISO 8601 scheduling."""
        self.helper.schedule_iso(
            message_callback=self.process_data,
            duration_period=self.cfg.connector_duration_period,
        )

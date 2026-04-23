"""
V2Secure Honeypot Connector for OpenCTI.

Reads inbound source-IP observations from a honeypot CSV log
(``IP_Reputation.csv``) and pushes them into OpenCTI as STIX Indicators
+ IPv4 Observables.

Pipeline:
  1. Parse CSV          — deduplicate by source IP, keep last_seen +
                          accumulated services / countries.
  2. Push to OpenCTI    — STIX Indicator + Observable + Relationship bundles.

Uses the same two-phase bundle-sending strategy as the other v2 connectors
to prevent race conditions:
  Phase 1: Send all entity bundles (Indicators + Observables)
  Phase 2: Wait ``relationship_delay`` seconds, then send relationship bundles
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

# Ensure src/ is on sys.path so bare imports work from any working directory.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config import ConnectorConfig
from parsers.honeypot import HoneypotRecord, group_by_group, parse_csv
from stix_builders.indicator import create_indicator, get_author
from stix_builders.observable import create_observable
from stix_builders.relationship import create_based_on

logger = logging.getLogger(__name__)


class HoneypotConnector:
    """OpenCTI EXTERNAL_IMPORT connector for V2Secure honeypot data."""

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

    # ------------------------------------------------------------------
    # Main processing loop — called by the scheduler
    # ------------------------------------------------------------------

    def process_data(self) -> None:
        """Run one sync cycle."""
        self.helper.connector_logger.info(
            "Honeypot connector: starting sync cycle"
        )

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
    # 2-step pipeline
    # ------------------------------------------------------------------

    def _run_sync(self) -> None:
        # Step 1: Parse CSV
        self.helper.connector_logger.info(
            f"Step 1/2: parsing honeypot CSV at {self.cfg.honeypot_file_path}"
        )
        records = parse_csv(self.cfg.honeypot_file_path)
        if not records:
            self.helper.connector_logger.info(
                "No honeypot records to import"
            )
            return

        for group, ips in sorted(group_by_group(records).items()):
            self.helper.connector_logger.info(
                f"Parsed: group={group}, count={len(ips)}"
            )

        # Step 2: Push to OpenCTI
        self.helper.connector_logger.info(
            f"Step 2/2: push {len(records)} honeypot IOCs to OpenCTI"
        )
        self._push_records(records)

    # ------------------------------------------------------------------
    # STIX bundle creation and push
    # ------------------------------------------------------------------

    def _push_records(self, records: list[HoneypotRecord]) -> None:
        """Build STIX bundles and send to OpenCTI in batches."""
        bundle_size = self.cfg.honeypot_bundle_size
        total_synced = 0

        work_id = self.helper.api.work.initiate_work(
            self.helper.connect_id,
            f"V2Secure honeypot sync ({len(records)} IOCs)",
        )

        # --- Phase 1: Send entity bundles, collect relationships ---
        pending_rels: list[str] = []

        for i in range(0, len(records), bundle_size):
            batch = records[i : i + bundle_size]
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
                f"Phase 1 done: {total_synced} entity bundles sent. "
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

        message = (
            f"Synced {total_synced}/{len(records)} IOCs from V2Secure honeypot"
        )
        self.helper.api.work.to_processed(work_id, message)
        self.helper.connector_logger.info(message)

    def _build_bundles(
        self, batch: list[HoneypotRecord]
    ) -> tuple[Bundle | None, Bundle | None, int]:
        """Build STIX2 Bundles from a batch of honeypot records."""
        entities: list[Any] = [get_author()]
        relationships: list[Any] = []

        for record in batch:
            try:
                indicator = create_indicator(
                    record, valid_days=self.cfg.honeypot_valid_days
                )
                observable = create_observable(record)
                rel = create_based_on(indicator.id, observable.id, record)
                entities.append(indicator)
                entities.append(observable)
                relationships.append(rel)
            except Exception:
                self.helper.connector_logger.warning(
                    f"Failed to build STIX for {record.source_ip}",
                    exc_info=True,
                )

        built = len(relationships)
        if built == 0:
            return None, None, 0

        entities_bundle = Bundle(objects=entities, allow_custom=True)
        rels_bundle = Bundle(objects=relationships, allow_custom=True)
        return entities_bundle, rels_bundle, built

    # ------------------------------------------------------------------
    # Entry point
    # ------------------------------------------------------------------

    def start(self) -> None:
        """Start the connector with ISO 8601 scheduling."""
        self.helper.schedule_iso(
            message_callback=self.process_data,
            duration_period=self.cfg.connector_duration_period,
        )

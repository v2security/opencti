"""
Maltrail IOC Connector for OpenCTI.

Daily sync from the maltrail GitHub repository. Clones the repo,
compares with previous run using SHA256, parses changed IOC files,
and pushes STIX Indicators (IP + Domain) into OpenCTI.

Four-step pipeline:
  1. Clone + Rotate  — git clone --depth 1, rotate old/new directories
  2. Compare          — SHA256 diff old vs new .txt files
  3. Parse IOCs       — clean lines, build value → label map
  4. Push to OpenCTI  — STIX Indicator + Observable + Relationship bundles

Uses two-phase bundle sending to prevent race conditions:
  Phase 1: Send all entity bundles (Indicators + Observables)
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config import ConnectorConfig, TRAIL_LABELS
from trail.clone import clone_and_rotate
from trail.compare import compare
from trail.parser import classify_ioc, group_by_label, parse
from stix_builders.indicator import create_indicator, get_author
from stix_builders.observable import create_observable
from stix_builders.relationship import create_based_on

logger = logging.getLogger(__name__)


class MaltrailConnector:
    """OpenCTI EXTERNAL_IMPORT connector for maltrail IOC data."""

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
        """Run one sync cycle (4 steps)."""
        self.helper.connector_logger.info("Maltrail connector: starting sync cycle")

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
    # 4-step pipeline
    # ------------------------------------------------------------------

    def _run_sync(self) -> None:
        # Step 1: Clone + Rotate
        self.helper.connector_logger.info("Step 1/4: clone and rotate")
        result = clone_and_rotate(
            repo_url=self.cfg.maltrail_repo_url,
            data_dir=self.cfg.maltrail_data_dir,
        )
        self.helper.connector_logger.info(
            f"Clone done: new_dir={result.new_dir}, first_run={result.first_run}"
        )

        # Step 2: Compare (SHA256)
        self.helper.connector_logger.info("Step 2/4: compare old vs new")
        diff = compare(result.old_dir, result.new_dir)

        if not diff.all and len(diff.changed) == 0:
            self.helper.connector_logger.info(
                "No changes detected, nothing to update"
            )
            return

        if diff.all:
            self.helper.connector_logger.info(
                "Processing all files (first run)"
            )
        else:
            self.helper.connector_logger.info(
                f"Files changed: {len(diff.changed)}"
            )

        # Step 3: Parse IOCs
        self.helper.connector_logger.info("Step 3/4: parse IOCs")
        ioc_map = parse(
            result.new_dir, diff,
            root_file_label=self.cfg.maltrail_root_file_label,
        )

        grouped = group_by_label(ioc_map)
        for label in TRAIL_LABELS:
            self.helper.connector_logger.info(
                f"Parsed: label={label}, count={len(grouped[label])}"
            )

        if len(ioc_map) == 0:
            self.helper.connector_logger.info("No IOCs to update")
            return

        # Step 4: Push to OpenCTI
        self.helper.connector_logger.info(
            f"Step 4/4: push {len(ioc_map)} IOCs to OpenCTI"
        )
        self._push_iocs(ioc_map)

    # ------------------------------------------------------------------
    # STIX bundle creation and push
    # ------------------------------------------------------------------

    def _push_iocs(self, ioc_map: dict[str, str]) -> None:
        """Build STIX bundles and send to OpenCTI in batches.

        Uses two-phase sending:
          Phase 1: Send all entity bundles, collect relationship bundles
          Phase 2: Wait relationship_delay, then send relationship bundles
        """
        items = list(ioc_map.items())
        bundle_size = self.cfg.maltrail_bundle_size
        total_synced = 0

        work_id = self.helper.api.work.initiate_work(
            self.helper.connect_id,
            f"Maltrail IOC sync ({len(items)} IOCs)",
        )

        # --- Phase 1: Send entity bundles, collect relationships ---
        pending_rels: list[str] = []  # serialized relationship bundles

        for i in range(0, len(items), bundle_size):
            batch = items[i : i + bundle_size]
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

        message = f"Synced {total_synced}/{len(items)} IOCs from maltrail"
        self.helper.api.work.to_processed(work_id, message)
        self.helper.connector_logger.info(message)

    def _build_bundles(
        self, batch: list[tuple[str, str]]
    ) -> tuple[Bundle | None, Bundle | None, int]:
        """Build STIX2 Bundles from a batch of IOCs.

        Returns (entities_bundle, relationships_bundle, count).
        Entities and Relationships are split to avoid race conditions.
        """
        entities: list[Any] = [get_author()]
        relationships: list[Any] = []

        for value, (category, file_tag) in batch:
            ioc_type = classify_ioc(value)
            try:
                ind = create_indicator(
                    value=value,
                    label=category,
                    ioc_type=ioc_type,
                    valid_days=self.cfg.maltrail_valid_days,
                    file_tag=file_tag,
                )
                obs = create_observable(
                    value=value,
                    label=category,
                    ioc_type=ioc_type,
                    file_tag=file_tag,
                )
                rel = create_based_on(ind, obs)
                entities.append(ind)
                entities.append(obs)
                relationships.append(rel)
            except Exception:
                self.helper.connector_logger.warning(
                    f"Failed to build STIX for {value}", exc_info=True
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

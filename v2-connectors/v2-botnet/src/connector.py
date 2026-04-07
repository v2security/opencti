from __future__ import annotations

import json
import logging
import os
import sys
import time
from pathlib import Path

import yaml
from dotenv import load_dotenv
from pycti import OpenCTIConnectorHelper, get_config_variable

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

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

from parsers.botnet import parse_file
from stix_builder.bundle import build_bundles

logger = logging.getLogger(__name__)


class BotnetConnector:
    def __init__(self):
        config_path = os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "..", "config.yml"
        )
        raw_config: dict = {}
        if os.path.isfile(config_path):
            with open(config_path, encoding="utf-8") as f:
                raw_config = yaml.safe_load(f) or {}

        self.helper = OpenCTIConnectorHelper(raw_config)

        default_storage = str(
            Path(__file__).resolve().parents[2] / "data" / "botnet"
        )
        self.storage_dir = Path(
            get_config_variable(
                "STORAGE_DIR",
                ["botnet", "storage_dir"],
                raw_config,
                default=default_storage,
            )
        )

        self.connector_duration_period = get_config_variable(
            "CONNECTOR_DURATION_PERIOD",
            ["connector", "duration_period"],
            raw_config,
            default="PT5M",
        )

        self.relationship_delay = int(
            get_config_variable(
                "RELATIONSHIP_DELAY",
                ["connector", "relationship_delay"],
                raw_config,
                default=600,
            )
        )

    def process_data(self) -> None:
        self.helper.connector_logger.info("Botnet connector: starting sync cycle")

        if not self.storage_dir.exists():
            self.helper.connector_logger.warning(
                f"Storage dir does not exist: {self.storage_dir}"
            )
            return

        json_files = sorted(self.storage_dir.glob("*.json"))
        if not json_files:
            self.helper.connector_logger.info(
                f"No JSON files found in {self.storage_dir}"
            )
            return

        # Two-phase sending: collect all relationship bundles across files,
        # send them after a delay to let entities be processed first.
        pending_rels: list[tuple[str, str]] = []  # (work_id, serialized_bundle)

        for json_file in json_files:
            try:
                rels = self._process_file(json_file)
                pending_rels.extend(rels)
            except Exception:
                self.helper.connector_logger.error(
                    f"Failed to process file {json_file.name}"
                )

        if pending_rels:
            delay = self.relationship_delay
            self.helper.connector_logger.info(
                f"Phase 1 done. Waiting {delay}s before sending "
                f"{len(pending_rels)} relationship bundles…"
            )
            time.sleep(delay)

            self.helper.connector_logger.info(
                f"Phase 2: sending {len(pending_rels)} relationship bundles"
            )
            for work_id, rels_data in pending_rels:
                self.helper.send_stix2_bundle(
                    rels_data,
                    work_id=work_id,
                    update=True,
                )

    def _process_file(self, json_file: Path) -> list[tuple[str, str]]:
        """Process one JSON file. Returns list of (work_id, rels_bundle_json)
        for deferred relationship sending."""
        self.helper.connector_logger.info(f"Processing file: {json_file.name}")

        try:
            with json_file.open(encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, ValueError):
            self.helper.connector_logger.error(
                f"Malformed JSON in {json_file.name} — deleting"
            )
            json_file.unlink(missing_ok=True)
            return []

        events = parse_file(data)
        if not events:
            self.helper.connector_logger.info(
                f"No events found in {json_file.name}"
            )
            json_file.unlink(missing_ok=True)
            return []

        work_id = self.helper.api.work.initiate_work(
            self.helper.connect_id,
            f"Botnet IOC ({json_file.name}, {len(events)} events)",
        )

        entities_bundle, rels_bundle, synced = build_bundles(events)
        if entities_bundle is None:
            message = f"Synced 0/{len(events)} indicators from {json_file.name}"
            self.helper.api.work.to_processed(work_id, message)
            self.helper.connector_logger.info(message)
            json_file.unlink(missing_ok=True)
            return []

        # Phase 1: Send entities now
        self.helper.send_stix2_bundle(
            entities_bundle.serialize(),
            work_id=work_id,
            update=True,
        )

        message = f"Synced {synced}/{len(events)} indicators from {json_file.name}"
        self.helper.api.work.to_processed(work_id, message)
        self.helper.connector_logger.info(message)
        json_file.unlink(missing_ok=True)

        # Collect relationships for deferred sending
        if rels_bundle is not None:
            return [(work_id, rels_bundle.serialize())]
        return []

    def start(self) -> None:
        self.helper.schedule_iso(
            message_callback=self.process_data,
            duration_period=self.connector_duration_period,
        )

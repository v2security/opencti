#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from pathlib import Path

import yaml

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Load .env from v2-connectors/ (walk up from this file's location)
def _load_env() -> None:
    try:
        from dotenv import load_dotenv
    except ImportError:
        return
    current = Path(__file__).resolve().parent
    for _ in range(6):
        env_file = current / ".env"
        if env_file.is_file():
            load_dotenv(env_file, override=False)
            return
        current = current.parent

_load_env()

# Load config.yml for non-sensitive settings
def _load_config() -> dict:
    config_path = Path(__file__).resolve().parent.parent / "config.yml"
    if config_path.is_file():
        with open(config_path, encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    return {}

_RAW_CONFIG = _load_config()

from pycti import get_config_variable
from parsers.botnet import parse_file
from stix_builder.bundle import build_bundles

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


def _build_opencti_config() -> dict:
    """Build OpenCTI connector config from config.yml + env vars."""
    url = get_config_variable("OPENCTI_URL", ["opencti", "url"], _RAW_CONFIG, default="http://localhost:8080")
    token = get_config_variable("OPENCTI_TOKEN", ["opencti", "token"], _RAW_CONFIG)
    if not token:
        logger.error("OPENCTI_TOKEN is not set — add it to .env or export the env var")
        sys.exit(1)
    return {
        "opencti": {"url": url, "token": token},
        "connector": {
            "id": get_config_variable("CONNECTOR_ID", ["connector", "id"], _RAW_CONFIG,
                                      default="b2c3d4e5-f6a7-8901-bcde-f12345678901"),
            "type": get_config_variable("CONNECTOR_TYPE", ["connector", "type"], _RAW_CONFIG,
                                        default="EXTERNAL_IMPORT"),
            "name": get_config_variable("CONNECTOR_NAME", ["connector", "name"], _RAW_CONFIG,
                                        default="Botnet IOC"),
            "scope": get_config_variable("CONNECTOR_SCOPE", ["connector", "scope"], _RAW_CONFIG,
                                         default="indicator"),
            "log_level": get_config_variable("CONNECTOR_LOG_LEVEL", ["connector", "log_level"], _RAW_CONFIG,
                                             default="info"),
        },
    }


_DEFAULT_DATA_DIR = Path(
    get_config_variable(
        "STORAGE_DIR", ["botnet", "storage_dir"], _RAW_CONFIG,
        default="/opt/connector/data",
    )
)


def _collect_files(file_arg: str | None) -> list[Path]:
    """Return list of JSON files to process."""
    if file_arg:
        return [Path(file_arg)]
    if _DEFAULT_DATA_DIR.exists():
        files = sorted(_DEFAULT_DATA_DIR.glob("*.json"))
        if files:
            return files
        logger.error("No JSON files found in %s", _DEFAULT_DATA_DIR)
    else:
        logger.error("Default data dir not found: %s", _DEFAULT_DATA_DIR)
    return []


def main():
    parser = argparse.ArgumentParser(
        description="Dev: build STIX Indicator bundle từ botnet JSON file"
    )
    parser.add_argument(
        "file", nargs="?", default=None,
        help="Path to botnet JSON file (mặc định: scan data/botnet/*.json)",
    )
    parser.add_argument("--dry-run", "-n", action="store_true",
                        help="In STIX bundle ra stdout, không gửi OpenCTI")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="In parsed event trước khi build")
    args = parser.parse_args()

    files = _collect_files(args.file)
    if not files:
        sys.exit(1)

    helper = None  # lazy init — created once on first non-dry-run send

    for file_path in files:
        logger.info("Loading: %s", file_path)
        with open(file_path, encoding="utf-8") as f:
            data = json.load(f)

        events = parse_file(data)
        logger.info("Parsed %d event(s)", len(events))

        if not events:
            logger.warning("No events found in %s — skipping", file_path.name)
            continue

        entities_bundle, rels_bundle, synced = build_bundles(events, verbose=args.verbose)
        if entities_bundle is None:
            logger.warning("No indicators built from %s — skipping", file_path.name)
            continue

        if args.dry_run:
            print(entities_bundle.serialize(pretty=True))
            if rels_bundle is not None:
                print(rels_bundle.serialize(pretty=True))
            logger.info("Dry run — bundle NOT sent to OpenCTI")
        else:
            from pycti import OpenCTIConnectorHelper

            if helper is None:
                helper = OpenCTIConnectorHelper(_build_opencti_config())
            work_id = helper.api.work.initiate_work(
                helper.connect_id,
                f"Botnet IOC Enrich ({file_path.name}, {len(events)} events)",
            )
            helper.send_stix2_bundle(
                entities_bundle.serialize(),
                work_id=work_id,
                update=True,
            )
            if rels_bundle is not None:
                helper.send_stix2_bundle(
                    rels_bundle.serialize(),
                    work_id=work_id,
                    update=True,
                )
            helper.api.work.to_processed(
                work_id,
                f"Synced {synced} indicators from {file_path.name}",
            )
            logger.info("Sent %d indicators to OpenCTI", synced)


if __name__ == "__main__":
    main()

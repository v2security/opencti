#!/usr/bin/env python3
"""
Dev helper: run the connector for a single CVE ID or an entire file.

Usage:
    cd v2-connectors/v2-nvd/src && conda activate opencti
    
    # Fetch from NVD API and send to OpenCTI:
    python dev_run.py CVE-2025-15112

    # Fetch from NVD API, print STIX bundle only (don't send):
    python dev_run.py CVE-2025-15112 --dry-run

    # Load from local JSON file instead of NVD API:
    python dev_run.py CVE-2025-15112 --file ../.data/nvd_cve_20260311.json

    # Combine: local file + dry run:
    python dev_run.py CVE-2025-15112 --file ../.data/nvd_cve_20260311.json --dry-run

    # Process ALL CVEs in a local JSON file (dry run):
    python dev_run.py --file-all ../.data/nvd_cve_20260311.json --dry-run

    # Process ALL CVEs in a file and send to OpenCTI:
    python dev_run.py --file-all ../.data/nvd_cve_20260311.json
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from typing import Any

from dotenv import load_dotenv

# Load .env from v2-connectors root (two levels up from src/)
_env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".env")
load_dotenv(_env_path, override=False)

# Map .env names to what pycti expects (like docker-compose does)
if not os.environ.get("OPENCTI_TOKEN") and os.environ.get("OPENCTI_ADMIN_TOKEN"):
    os.environ["OPENCTI_TOKEN"] = os.environ["OPENCTI_ADMIN_TOKEN"]
if not os.environ.get("CONNECTOR_ID") and os.environ.get("CONNECTOR_V2_NVD_ID"):
    os.environ["CONNECTOR_ID"] = os.environ["CONNECTOR_V2_NVD_ID"]

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import yaml
from stix2 import Bundle

from clients.epss import EpssApiClient
from clients.nvd import NvdApiClient
from config import ConnectorConfig
from parsers.cpe import extract_vulnerable_cpes
from parsers.cve import get_description
from stix_builders.relationship import create_relationship
from stix_builders.software import create_software
from stix_builders.vulnerability import create_vulnerability, get_author

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


def _load_config() -> dict:
    config_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "config.yml"
    )
    if os.path.isfile(config_path):
        with open(config_path, encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    return {}


def _load_all_cves_from_file(filepath: str) -> list[dict]:
    """Load all CVEs from a local NVD JSON file."""
    with open(filepath, encoding="utf-8") as f:
        data = json.load(f)
    cves = []
    for entry in data.get("vulnerabilities", []):
        cve = entry.get("cve", {})
        if cve.get("id"):
            cves.append(cve)
    return cves


def _find_cve_in_file(filepath: str, cve_id: str) -> dict | None:
    """Search a local NVD JSON file for a specific CVE ID."""
    with open(filepath, encoding="utf-8") as f:
        data = json.load(f)
    for entry in data.get("vulnerabilities", []):
        cve = entry.get("cve", {})
        if cve.get("id") == cve_id:
            return cve
    return None


def _fetch_cve_from_api(cfg: ConnectorConfig, cve_id: str) -> dict | None:
    """Fetch a single CVE from the NVD API by ID."""
    nvd = NvdApiClient(
        base_url=cfg.nvd_base_url,
        api_key=cfg.nvd_api_key,
        request_timeout=cfg.nvd_request_timeout,
    )
    # NVD API supports cveId parameter directly
    import json as _json
    import time
    import urllib.parse
    import urllib.request

    params = {"cveId": cve_id}
    url = f"{nvd.base_url}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url)
    if nvd.api_key:
        req.add_header("apiKey", nvd.api_key)

    try:
        with urllib.request.urlopen(req, timeout=nvd.request_timeout) as resp:
            data = _json.loads(resp.read().decode())
        vulns = data.get("vulnerabilities", [])
        if vulns:
            return vulns[0].get("cve")
    except Exception:
        logger.exception("Failed to fetch %s from NVD API", cve_id)
    return None


def _build_bundle(cve_data: dict, epss_data: dict | None) -> Bundle | None:
    if not get_description(cve_data):
        logger.warning("CVE %s has no description, skipping", cve_data.get("id"))
        return None

    vuln = create_vulnerability(cve_data, epss_data=epss_data)
    objects = [get_author(), vuln]

    for cpe_match in extract_vulnerable_cpes(cve_data):
        sw = create_software(cpe_match)
        rel = create_relationship(
            sw, vuln, hardware_cpes=cpe_match.get("_hardware_cpes")
        )
        objects.extend([sw, rel])

    # Tag vulnerability as having relationships if any software was linked
    if len(objects) > 2:
        vuln = vuln.new_version(labels=list(vuln.get("labels", [])) + ["has-rel"])
        objects[1] = vuln

    return Bundle(objects=objects, allow_custom=True)


def _write_json(sample_dir: str, cve_id: str, suffix: str, obj: Any) -> None:
    path = os.path.join(sample_dir, f"{cve_id}.{suffix}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, ensure_ascii=False)


def _process_single_cve(
    cve_data: dict,
    epss_data: dict | None,
    sample_dir: str,
    dry_run: bool,
    raw_config: dict,
    helper: Any = None,
) -> bool:
    """Process one CVE: build bundle, save samples, send/print. Returns True on success."""
    cve_id = cve_data["id"]

    bundle = _build_bundle(cve_data, epss_data)
    if bundle is None:
        return False

    # Save samples
    os.makedirs(sample_dir, exist_ok=True)
    _write_json(sample_dir, cve_id, "nvd", cve_data)
    if epss_data:
        _write_json(sample_dir, cve_id, "epss", epss_data)
    _write_json(sample_dir, cve_id, "stix", json.loads(bundle.serialize()))

    if dry_run:
        print(bundle.serialize(pretty=True))
        logger.info("[%s] Dry run — bundle NOT sent to OpenCTI", cve_id)
    else:
        if helper is None:
            from pycti import OpenCTIConnectorHelper
            helper = OpenCTIConnectorHelper(raw_config)

        work_id = helper.api.work.initiate_work(
            helper.connect_id,
            f"Dev: {cve_id}",
        )
        helper.send_stix2_bundle(
            bundle.serialize(),
            work_id=work_id,
            update=True,
        )
        helper.api.work.to_processed(work_id, f"Dev: {cve_id} sent")
        logger.info("Sent %s to OpenCTI (%d objects)", cve_id, len(bundle.objects))

    return True


def main():
    parser = argparse.ArgumentParser(
        description="Dev: run NVD connector for a single CVE or an entire file"
    )
    parser.add_argument("cve_id", nargs="?", help="CVE ID, e.g. CVE-2025-15112")
    parser.add_argument(
        "--file", "-f",
        help="Load CVE from local JSON file instead of NVD API",
    )
    parser.add_argument(
        "--file-all", "-F",
        metavar="FILE",
        help="Process ALL CVEs in a local JSON file",
    )
    parser.add_argument(
        "--dry-run", "-n",
        action="store_true",
        help="Print STIX bundle only, don't send to OpenCTI",
    )
    parser.add_argument(
        "--no-epss",
        action="store_true",
        help="Skip EPSS enrichment",
    )
    args = parser.parse_args()

    # Validate args
    if args.file_all and args.cve_id:
        parser.error("Cannot use both cve_id and --file-all at the same time")
    if not args.file_all and not args.cve_id:
        parser.error("Either cve_id or --file-all is required")

    raw_config = _load_config()
    cfg = ConnectorConfig(raw_config)

    sample_dir = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", ".sample"
    )

    # --file-all mode: process all CVEs in a file
    if args.file_all:
        logger.info("Loading all CVEs from %s", args.file_all)
        all_cves = _load_all_cves_from_file(args.file_all)
        if not all_cves:
            logger.error("No CVEs found in %s", args.file_all)
            sys.exit(1)
        logger.info("Found %d CVEs in file", len(all_cves))

        # Batch EPSS fetch for all CVE IDs at once
        epss_map: dict[str, dict] = {}
        if cfg.epss_enabled and not args.no_epss:
            cve_ids = [c["id"] for c in all_cves]
            logger.info("Fetching EPSS scores for %d CVEs", len(cve_ids))
            epss = EpssApiClient(
                api_url=cfg.epss_api_url,
                batch_size=cfg.epss_batch_size,
                request_timeout=cfg.epss_request_timeout,
                request_delay=cfg.epss_request_delay,
            )
            epss_map = epss.fetch_scores(cve_ids)
            logger.info("EPSS: received scores for %d CVEs", len(epss_map))

        # Setup helper once for non-dry-run
        helper = None
        if not args.dry_run:
            from pycti import OpenCTIConnectorHelper
            raw_config.setdefault("connector", {})["run_and_terminate"] = True
            _original_excepthook = sys.excepthook
            try:
                helper = OpenCTIConnectorHelper(raw_config)
            except Exception as e:
                logger.error("Failed to connect to OpenCTI: %s", e)
                sys.exit(1)
            finally:
                sys.excepthook = _original_excepthook

        success = 0
        failed = 0
        for i, cve_data in enumerate(all_cves, 1):
            cve_id = cve_data["id"]
            logger.info("[%d/%d] Processing %s", i, len(all_cves), cve_id)
            epss_data = epss_map.get(cve_id)
            ok = _process_single_cve(
                cve_data, epss_data, sample_dir,
                args.dry_run, raw_config, helper,
            )
            if ok:
                success += 1
            else:
                failed += 1

        logger.info(
            "Done: %d success, %d failed out of %d CVEs",
            success, failed, len(all_cves),
        )
        if failed:
            sys.exit(1)
        return

    # Single CVE mode
    if args.file:
        logger.info("Loading %s from %s", args.cve_id, args.file)
        cve_data = _find_cve_in_file(args.file, args.cve_id)
    else:
        logger.info("Fetching %s from NVD API", args.cve_id)
        cve_data = _fetch_cve_from_api(cfg, args.cve_id)

    if cve_data is None:
        logger.error("CVE %s not found", args.cve_id)
        sys.exit(1)

    logger.info("Found %s (status: %s)", cve_data["id"], cve_data.get("vulnStatus"))

    # EPSS enrichment
    epss_data = None
    if cfg.epss_enabled and not args.no_epss:
        logger.info("Fetching EPSS score for %s", args.cve_id)
        epss = EpssApiClient(
            api_url=cfg.epss_api_url,
            batch_size=cfg.epss_batch_size,
            request_timeout=cfg.epss_request_timeout,
            request_delay=cfg.epss_request_delay,
        )
        scores = epss.fetch_scores([args.cve_id])
        epss_data = scores.get(args.cve_id)
        if epss_data:
            logger.info("EPSS: score=%s percentile=%s", epss_data["epss"], epss_data["percentile"])
        else:
            logger.info("No EPSS data available")

    os.makedirs(sample_dir, exist_ok=True)
    ok = _process_single_cve(
        cve_data, epss_data, sample_dir,
        args.dry_run, raw_config,
    )
    if not ok:
        sys.exit(1)
    logger.info("Saved sample files to .sample/%s.*.json", args.cve_id)


if __name__ == "__main__":
    main()

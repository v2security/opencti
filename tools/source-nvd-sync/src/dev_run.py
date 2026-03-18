#!/usr/bin/env python3
"""
Dev helper: run the connector for a single CVE ID.

Usage:
    cd tools/source-nvd-sync/src && conda activate opencti
    
    # Fetch from NVD API and send to OpenCTI:
    python dev_run.py CVE-2025-15112

    # Fetch from NVD API, print STIX bundle only (don't send):
    python dev_run.py CVE-2025-15112 --dry-run

    # Load from local JSON file instead of NVD API:
    python dev_run.py CVE-2025-15112 --file ../data/nvd-cve/nvd_cve_20260311.json

    # Combine: local file + dry run:
    python dev_run.py CVE-2025-15112 --file ../data/nvd-cve/nvd_cve_20260311.json --dry-run
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from typing import Any

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

    return Bundle(objects=objects, allow_custom=True)


def _write_json(sample_dir: str, cve_id: str, suffix: str, obj: Any) -> None:
    path = os.path.join(sample_dir, f"{cve_id}.{suffix}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, ensure_ascii=False)


def main():
    parser = argparse.ArgumentParser(
        description="Dev: run NVD connector for a single CVE"
    )
    parser.add_argument("cve_id", help="CVE ID, e.g. CVE-2025-15112")
    parser.add_argument(
        "--file", "-f",
        help="Load CVE from local JSON file instead of NVD API",
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

    raw_config = _load_config()
    cfg = ConnectorConfig(raw_config)

    # 1. Get CVE data
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

    # 2. EPSS enrichment
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

    # 3. Build bundle
    bundle = _build_bundle(cve_data, epss_data)
    if bundle is None:
        sys.exit(1)

    # 4. Save samples to .sample/
    sample_dir = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", ".sample"
    )
    os.makedirs(sample_dir, exist_ok=True)
    _save = lambda suffix, obj: _write_json(sample_dir, args.cve_id, suffix, obj)
    _save("nvd", cve_data)
    if epss_data:
        _save("epss", epss_data)
    _save("stix", json.loads(bundle.serialize()))
    logger.info("Saved sample files to .sample/%s.*.json", args.cve_id)

    # 5. Output
    bundle_json = bundle.serialize(pretty=True)

    if args.dry_run:
        print(bundle_json)
        logger.info("Dry run — bundle NOT sent to OpenCTI")
    else:
        from pycti import OpenCTIConnectorHelper

        helper = OpenCTIConnectorHelper(raw_config)
        work_id = helper.api.work.initiate_work(
            helper.connect_id,
            f"Dev: {args.cve_id}",
        )
        helper.send_stix2_bundle(
            bundle.serialize(),
            work_id=work_id,
            update=True,
        )
        helper.api.work.to_processed(work_id, f"Dev: {args.cve_id} sent")
        logger.info("Sent %s to OpenCTI (%d objects)", args.cve_id, len(bundle.objects))


if __name__ == "__main__":
    main()

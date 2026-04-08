#!/usr/bin/env python3
import os
import json
import time
import requests
from datetime import datetime, timedelta
from pathlib import Path

try:
    from dotenv import load_dotenv
    _env = Path(__file__).resolve().parent.parent / ".env"
    if _env.is_file():
        load_dotenv(_env, override=False)
except ImportError:
    pass

API_KEY = os.environ.get("NVD_API_KEY", "")
if not API_KEY:
    raise SystemExit("NVD_API_KEY not set. Export it or add to v2-connectors/.env")

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".data")
BASE_URL = "https://services.nvd.nist.gov/rest/json/cves/2.0"


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # lấy ngày (UTC - 2)
    yesterday = datetime.utcnow() - timedelta(days=2)

    date_str = yesterday.strftime("%Y-%m-%d")
    file_str = yesterday.strftime("%Y%m%d")

    start = f"{date_str}T00:00:00.000"
    end = f"{date_str}T23:59:59.000"

    page_size = 2000
    start_index = 0

    all_vulns = []

    print(f"Downloading CVE for {date_str}")

    while True:
        url = (
            f"{BASE_URL}"
            f"?lastModStartDate={start}"
            f"&lastModEndDate={end}"
            f"&resultsPerPage={page_size}"
            f"&startIndex={start_index}"
        )

        print(f"Fetching startIndex = {start_index}")

        headers = {"apiKey": API_KEY}

        try:
            resp = requests.get(url, headers=headers, timeout=30)
            resp.raise_for_status()
        except Exception as e:
            print(f"Request error: {e}")
            break

        data = resp.json()
        vulns = data.get("vulnerabilities", [])

        if not vulns:
            break

        all_vulns.extend(vulns)
        start_index += page_size

        time.sleep(1)

    print(f"Total CVE: {len(all_vulns)}")

    output_file = os.path.join(OUTPUT_DIR, f"nvd_cve_{file_str}.json")

    with open(output_file, "w", encoding="utf-8") as f:
        json.dump({"vulnerabilities": all_vulns}, f, indent=2, ensure_ascii=False)

    print(f"Saved to {output_file}")


if __name__ == "__main__":
    main()
#!/usr/bin/env python3
"""hashlist_sync — standalone entry point.

Usage:
    python -m hashlist_sync.main            # run forever
    python -m hashlist_sync.main --once     # single drain
"""

from __future__ import annotations

import sys

from hashlist_sync.scheduler import HashlistScheduler
from util.config import load_config
from util.logger import get_logger

def main() -> None:
    cfg = load_config()
    log = get_logger("hashlist_sync", level=str(cfg.get("log_level", "INFO")).upper())

    octi = cfg["opencti"]
    mysql = cfg["mysql"]
    sched = cfg.get("scheduler", {})

    log.info("=" * 60)
    log.info("  Hashlist Sync (Hash + VirusTotal)")
    log.info("  OpenCTI    : %s", octi["api_url"])
    log.info("  MySQL      : %s@%s:%s/%s", mysql["user"], mysql["host"],
             mysql["port"], mysql["database"])
    log.info("  Batch      : %s   Idle: %ss",
             sched.get("vt_batch_size", 4),
             sched.get("idle_sleep_seconds", 60))
    log.info("  VT rate    : %s req/min", sched.get("vt_rate_limit", 4))
    log.info("  VT daily   : %s req/day", sched.get("vt_daily_quota", 500))
    log.info("  VT monthly : %s req/month", sched.get("vt_monthly_quota", 15500))
    log.info("  StartSync  : %s", sched.get("time_start_sync", "") or "(auto from MySQL)")
    log.info("  Score>=%s  Confidence>=%s",
             octi.get("min_score", 70), octi.get("min_confidence", 70))
    log.info("  VT         : %s",
             "enabled" if cfg.get("virustotal", {}).get("enabled") else "disabled")
    log.info("=" * 60)

    scheduler = HashlistScheduler(cfg)

    if "--once" in sys.argv:
        log.info("Running single drain (--once).")
        scheduler.run_once()
    else:
        scheduler.run_forever()


if __name__ == "__main__":
    main()

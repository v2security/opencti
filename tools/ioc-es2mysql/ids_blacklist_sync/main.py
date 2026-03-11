#!/usr/bin/env python3
"""ids_blacklist_sync — entry point for the IP/Domain blacklist sync process.

Usage:
    python -m ids_blacklist_sync.main            # run continuously
    python -m ids_blacklist_sync.main --once     # single drain then exit
"""

from __future__ import annotations

import sys

from ids_blacklist_sync.scheduler import BlacklistScheduler
from util.config import load_config
from util.logger import get_logger


def main() -> None:
    cfg = load_config()
    log = get_logger("ids_blacklist_sync", level=str(cfg.get("log_level", "INFO")).upper())

    octi = cfg["opencti"]
    mysql = cfg["mysql"]
    sched = cfg.get("scheduler", {})

    log.info("=" * 60)
    log.info("  IDS Blacklist Sync (IP/Domain + GeoIP)")
    log.info("  OpenCTI  : %s", octi["api_url"])
    log.info("  MySQL    : %s@%s:%s/%s", mysql["user"], mysql["host"], mysql["port"], mysql["database"])
    log.info("  Batch    : %s   Sleep: %ss   Idle: %ss",
             sched.get("geoip_batch_size", 50),
             sched.get("geoip_sleep_seconds", 5),
             sched.get("idle_sleep_seconds", 60))
    log.info("  StartSync: %s", sched.get("time_start_sync", "") or "(auto from MySQL)")
    log.info("  Score>=%s  Confidence>=%s", octi.get("min_score", 70), octi.get("min_confidence", 70))
    log.info("=" * 60)

    scheduler = BlacklistScheduler(cfg)

    if "--once" in sys.argv:
        log.info("Single drain mode (--once).")
        scheduler.run_once()
    else:
        scheduler.run_forever()


if __name__ == "__main__":
    main()

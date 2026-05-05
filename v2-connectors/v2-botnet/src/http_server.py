import hashlib
import json
import logging
import os
import queue
import re
import sys
import threading
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import uvicorn
import yaml
from dotenv import load_dotenv
from fastapi import FastAPI, Header, HTTPException, Request
from pycti import OpenCTIConnectorHelper, get_config_variable
from watchfiles import watch

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

# Load config.yml for non-sensitive settings
def _load_config() -> dict:
    config_path = Path(__file__).resolve().parent.parent / "config.yml"
    if config_path.is_file():
        with open(config_path, encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    return {}

_RAW_CONFIG = _load_config()

from parsers.botnet import parse_file
from stix_builder.bundle import build_bundles

logger = logging.getLogger(__name__)

# --- OpenCTI ConnectorHelper (registers connector + sends ping alive) ---
_helper: OpenCTIConnectorHelper | None = None

def _get_helper() -> OpenCTIConnectorHelper:
    global _helper
    if _helper is None:
        _helper = OpenCTIConnectorHelper(_RAW_CONFIG)
    return _helper




def _process_worker() -> None:
    helper = _get_helper()
    while True:
        path: Path = _file_queue.get()
        try:
            _handle_file(path, helper)
        except Exception:
            logger.exception("Worker: unhandled error processing %s", path.name)
        finally:
            _file_queue.task_done()


def _handle_file(path: Path, helper: OpenCTIConnectorHelper) -> None:
    logger.info("Worker: processing %s", path.name)
    try:
        with path.open(encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        logger.warning("Worker: file already processed/deleted %s — skipping", path.name)
        return
    except (json.JSONDecodeError, ValueError):
        logger.exception("Worker: malformed JSON in %s — deleting", path.name)
        path.unlink(missing_ok=True)
        return
    except OSError:
        logger.exception("Worker: failed to read %s — keeping file", path.name)
        return

    events = parse_file(data)
    if not events:
        logger.warning("Worker: no events in %s — deleting", path.name)
        path.unlink(missing_ok=True)
        return

    entities_bundle, rels_bundle, built = build_bundles(events)
    if entities_bundle is None:
        logger.warning("Worker: 0 indicators built from %s — deleting", path.name)
        path.unlink(missing_ok=True)
        return

    try:
        work_id = helper.api.work.initiate_work(
            helper.connect_id,
            f"Botnet IOC ({path.name}, {built} indicators)",
        )
        # Phase 1: Send entities (Indicators + Observables) first
        helper.send_stix2_bundle(
            entities_bundle.serialize(),
            work_id=work_id,
            update=True,
        )
        # Phase 2: Wait for entities to be processed, then send relationships
        if rels_bundle is not None:
            delay = int(get_config_variable(
                "RELATIONSHIP_DELAY",
                ["connector", "relationship_delay"],
                _RAW_CONFIG,
                default=60,
            ))
            logger.info(
                "Worker: waiting %ds before sending relationships for %s",
                delay, path.name,
            )
            time.sleep(delay)
            helper.send_stix2_bundle(
                rels_bundle.serialize(),
                work_id=work_id,
                update=True,
            )
        message = f"Synced {built} indicators from {path.name}"
        helper.api.work.to_processed(work_id, message)
        logger.info("Worker: pushed %d indicators from %s", built, path.name)
        path.unlink(missing_ok=True)
        logger.info("Worker: deleted %s", path.name)
    except Exception:
        logger.exception("Worker: push failed for %s — keeping file for retry", path.name)



_file_queue: queue.Queue = queue.Queue(
    maxsize=int(get_config_variable(
        "QUEUE_MAX_SIZE", ["http_server", "queue_max_size"], _RAW_CONFIG, default=500
    ))
)


@dataclass(frozen=True)
class ServerConfig:
    host: str
    port: int
    storage_dir: Path
    watch_dir: Optional[Path]
    max_file_size: int
    allowed_extensions: set[str]
    auth_token: str | None

    @staticmethod
    def from_config() -> "ServerConfig":
        default_storage_dir = "/opt/connector/data"

        raw_ext = get_config_variable(
            "ALLOWED_EXTENSIONS", ["http_server", "allowed_extensions"], _RAW_CONFIG, default=""
        )
        exts = {
            e.strip().lower().lstrip(".")
            for e in str(raw_ext).split(",")
            if e.strip()
        }

        raw_watch = os.getenv("WATCH_DIR")
        auth_token = get_config_variable(
            "AUTH_TOKEN",
            ["http_server", "auth_token"],
            _RAW_CONFIG,
            default="",
        )

        return ServerConfig(
            host=get_config_variable("HOST", ["http_server", "host"], _RAW_CONFIG, default="127.0.0.1"),
            port=int(get_config_variable("PORT", ["http_server", "port"], _RAW_CONFIG, default=8000)),
            storage_dir=Path(get_config_variable(
                "STORAGE_DIR", ["botnet", "storage_dir"], _RAW_CONFIG, default=default_storage_dir
            )).resolve(),
            watch_dir=Path(raw_watch).resolve() if raw_watch else None,
            max_file_size=int(get_config_variable(
                "MAX_FILE_SIZE", ["http_server", "max_file_size"], _RAW_CONFIG, default=50 * 1024 * 1024
            )),
            allowed_extensions=exts,
            auth_token=str(auth_token).strip() or None,
        )


CONFIG = ServerConfig.from_config()



def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _enforce_upload_access(x_api_key: str | None) -> None:
    if CONFIG.auth_token and x_api_key != CONFIG.auth_token:
        raise HTTPException(status_code=401, detail={"error": "invalid_api_key"})


app = FastAPI(
    title="Botnet Upload API",
    description="Upload botnet JSON files to be parsed and pushed to OpenCTI",
    version="1.0.0",
)


@app.get("/healthz", tags=["health"])
async def healthz():
    return {"status": "ok", "time": _now_iso()}


@app.get("/api/v1/config", tags=["config"])
async def get_config():
    return {
        "max_file_size": CONFIG.max_file_size,
        "allowed_extensions": sorted(CONFIG.allowed_extensions),
        "storage_dir": str(CONFIG.storage_dir),
    }


@app.post(
    "/api/v1/files",
    status_code=202,
    tags=["upload"],
)
async def upload_file(
    request: Request,
    x_api_key: str | None = Header(default=None, alias="X-Api-Key"),
):
    _enforce_upload_access(x_api_key)

    content = await request.body()
    if not content:
        raise HTTPException(status_code=400, detail="empty_body")
    if len(content) > CONFIG.max_file_size:
        raise HTTPException(
            status_code=413,
            detail={"error": "file_too_large", "max_bytes": CONFIG.max_file_size},
        )
    try:
        json.loads(content)
    except (json.JSONDecodeError, ValueError):
        raise HTTPException(status_code=400, detail="invalid_json")

    hasher = hashlib.sha256(content)
    file_id = str(uuid.uuid4())
    filename = f"{file_id}.json"
    target_path = CONFIG.storage_dir / filename

    target_path.parent.mkdir(parents=True, exist_ok=True)
    target_path.write_bytes(content)

    try:
        _file_queue.put_nowait(target_path)
    except queue.Full:
        target_path.unlink(missing_ok=True)
        raise HTTPException(
            status_code=503,
            detail={"error": "processing_queue_full", "queue_max_size": _file_queue.maxsize},
        )
    logger.info("Queued for processing: %s (queue size: %d)", filename, _file_queue.qsize())

    return {
        "id": file_id,
        "filename": filename,
        "bytes": len(content),
        "sha256": hasher.hexdigest(),
        "queued_at": _now_iso(),
        "status": "queued",
    }


def _folder_watcher() -> None:
    watch_dir = CONFIG.watch_dir or CONFIG.storage_dir
    logger.info("Folder watcher started on %s", watch_dir)
    watch_dir.mkdir(parents=True, exist_ok=True)
    for changes in watch(watch_dir):
        for change_type, path_str in changes:
            path = Path(path_str)
            if change_type.name == "added" and path.suffix == ".json" and path.is_file():
                logger.info("Folder watcher: detected new file %s", path.name)
                _file_queue.put(path)


def run() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
    )

    # Initialize helper early — registers connector + starts ping alive
    helper = _get_helper()
    logger.info("Connector registered with OpenCTI (id=%s)", helper.connect_id)

    CONFIG.storage_dir.mkdir(parents=True, exist_ok=True)

    worker = threading.Thread(target=_process_worker, daemon=True, name="botnet-worker")
    worker.start()
    logger.info("Background worker started")

    if CONFIG.watch_dir:
        watcher = threading.Thread(target=_folder_watcher, daemon=True, name="botnet-watcher")
        watcher.start()
    else:
        logger.info("Folder watcher disabled (WATCH_DIR not set)")

    logger.info(
        "Upload API running on %s:%d | Swagger UI: http://%s:%d/docs",
        CONFIG.host, CONFIG.port, CONFIG.host, CONFIG.port,
    )
    uvicorn.run(app, host=CONFIG.host, port=CONFIG.port)


if __name__ == "__main__":
    run()
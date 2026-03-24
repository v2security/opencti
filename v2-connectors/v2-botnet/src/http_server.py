import hashlib
import json
import logging
import os
import queue
import re
import sys
import threading
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, File, UploadFile, HTTPException, Security
from fastapi.security.api_key import APIKeyHeader
from watchfiles import watch

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Load .env from project root (walk up from this file's location)
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
from stix_builder.bundle import build_bundle
from pycti import OpenCTIApiClient

logger = logging.getLogger(__name__)


_OPENCTI_URL        = os.getenv("OPENCTI_URL", "http://localhost:8080")
_OPENCTI_TOKEN      = os.getenv("OPENCTI_TOKEN") or os.getenv("APP_ADMIN_TOKEN")
_OPENCTI_SSL_VERIFY = os.getenv("OPENCTI_SSL_VERIFY", "true").strip().lower() not in ("0", "false", "no")

def _get_opencti_client() -> OpenCTIApiClient:
    if not _OPENCTI_TOKEN:
        raise ValueError("OPENCTI_TOKEN is not set — add it to .env or set the env var")
    return OpenCTIApiClient(_OPENCTI_URL, _OPENCTI_TOKEN, ssl_verify=_OPENCTI_SSL_VERIFY)




def _process_worker() -> None:
    client = _get_opencti_client()
    while True:
        path: Path = _file_queue.get()
        try:
            _handle_file(path, client)
        except Exception:
            logger.exception("Worker: unhandled error processing %s", path.name)
            client = _get_opencti_client()
        finally:
            _file_queue.task_done()


def _handle_file(path: Path, client: OpenCTIApiClient) -> None:
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

    bundle = build_bundle(events)
    if bundle is None:
        logger.warning("Worker: 0 indicators built from %s — deleting", path.name)
        path.unlink(missing_ok=True)
        return

    try:
        built = len(bundle.objects) - 1
        client.stix2.import_bundle_from_json(bundle.serialize())
        logger.info("Worker: pushed %d indicators from %s", built, path.name)
        path.unlink(missing_ok=True)
        logger.info("Worker: deleted %s", path.name)
    except Exception:
        logger.exception("Worker: push failed for %s — keeping file for retry", path.name)



def _parse_int_env(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None:
        return default
    try:
        return int(value)
    except ValueError:
        return default


_file_queue: queue.Queue = queue.Queue(maxsize=_parse_int_env("QUEUE_MAX_SIZE", 500))


@dataclass(frozen=True)
class ServerConfig:
    host: str
    port: int
    storage_dir: Path
    watch_dir: Optional[Path]
    max_file_size: int
    auth_token: Optional[str]
    allowed_extensions: set[str]

    @staticmethod
    def from_env() -> "ServerConfig":
        default_storage_dir = (Path(__file__).resolve().parents[2] / "data" / "botnet")
        raw_ext = os.getenv("ALLOWED_EXTENSIONS", "")
        exts = {
            e.strip().lower().lstrip(".")
            for e in raw_ext.split(",")
            if e.strip()
        }
        raw_watch = os.getenv("WATCH_DIR")
        return ServerConfig(
            host=os.getenv("HOST", "0.0.0.0"),
            port=_parse_int_env("PORT", 8000),
            storage_dir=Path(os.getenv("STORAGE_DIR", str(default_storage_dir))).resolve(),
            watch_dir=Path(raw_watch).resolve() if raw_watch else None,
            max_file_size=_parse_int_env("MAX_FILE_SIZE", 50 * 1024 * 1024),
            auth_token=(os.getenv("AUTH_TOKEN") or os.getenv("HTTP_SERVER_API_KEY") or None),
            allowed_extensions=exts,
        )


CONFIG = ServerConfig.from_env()

_safe_name = re.compile(r"[^a-zA-Z0-9._-]+")

_api_key_header = APIKeyHeader(name="X-Api-Key", auto_error=False)


def _sanitize_filename(filename: str) -> str:
    cleaned = filename.strip().replace("\\", "/").split("/")[-1]
    cleaned = _safe_name.sub("_", cleaned)
    return cleaned[:255]


def _extension_allowed(filename: str) -> bool:
    if not CONFIG.allowed_extensions:
        return True
    ext = filename.rsplit(".", 1)
    if len(ext) < 2:
        return False
    return ext[1].lower() in CONFIG.allowed_extensions


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


async def _check_api_key(api_key: Optional[str] = Security(_api_key_header)) -> None:
    if not CONFIG.auth_token:
        return
    if api_key != CONFIG.auth_token:
        raise HTTPException(status_code=401, detail="unauthorized")


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
        "auth_enabled": bool(CONFIG.auth_token),
    }


@app.post(
    "/api/v1/files",
    status_code=202,
    tags=["upload"],
    dependencies=[Security(_check_api_key)],
)
async def upload_file(file: UploadFile = File(...)):
    safe_filename = _sanitize_filename(file.filename or "")
    if not safe_filename:
        raise HTTPException(status_code=400, detail="missing_or_invalid_filename")

    if not _extension_allowed(safe_filename):
        raise HTTPException(
            status_code=400,
            detail={
                "error": "extension_not_allowed",
                "allowed_extensions": sorted(CONFIG.allowed_extensions),
            },
        )

    _CHUNK = 64 * 1024  # 64 KB
    chunks: list[bytes] = []
    total = 0
    hasher = hashlib.sha256()
    while True:
        chunk = await file.read(_CHUNK)
        if not chunk:
            break
        total += len(chunk)
        if total > CONFIG.max_file_size:
            raise HTTPException(
                status_code=413,
                detail={"error": "file_too_large", "max_bytes": CONFIG.max_file_size},
            )
        chunks.append(chunk)
        hasher.update(chunk)

    if total == 0:
        raise HTTPException(status_code=400, detail="empty_body")

    content = b"".join(chunks)
    file_id = str(uuid.uuid4())
    target_path = CONFIG.storage_dir / f"{file_id}_{safe_filename}"

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
    logger.info("Queued for processing: %s (queue size: %d)", target_path.name, _file_queue.qsize())

    return {
        "id": file_id,
        "filename": safe_filename,
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
            if change_type.name == "added" and _extension_allowed(path.name) and path.is_file():
                logger.info("Folder watcher: detected new file %s", path.name)
                _file_queue.put(path)


def run() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
    )

    if not _OPENCTI_TOKEN:
        logger.error(
            "OPENCTI_TOKEN is not set — add it to .env or set the env var. Exiting."
        )
        raise SystemExit(1)

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
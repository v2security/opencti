# v2-botnet — Botnet IOC Connector

```
curl -X POST http://localhost:28080/api/v1/files \
  -F "file=@/workspace/tunv_opencti/v2-connectors/.data/botnet/sample_data.json"
```

Custom connector nhận file JSON botnet qua **HTTP API (FastAPI)**, parse thành STIX Indicator rồi push vào OpenCTI.

## Luồng xử lý

```
POST /api/v1/files (JSON file)
    → Lưu vào storage_dir
    → Connector daemon poll thư mục mỗi duration_period (default 5 phút)
    → parse_file() → build_bundle() → STIX Bundle (Indicator × N)
    → send_stix2_bundle() ──publish──→ RabbitMQ
    → OpenCTI worker consume từ queue ──→ import vào OpenCTI
    → Xóa file sau khi xử lý xong
```

## API Endpoints

| Method | Path | Mô tả |
|--------|------|-------|
| `GET` | `/docs` | Swagger UI |
| `GET` | `/healthz` | Health check |
| `GET` | `/api/v1/config` | Xem config hiện tại |
| `POST` | `/api/v1/files` | Upload JSON file (header `X-Api-Key` nếu bật auth) |

## STIX Output

Mỗi event trong JSON → 1 STIX `Indicator`:
- Pattern: `[ipv4-addr:value = '<source_ip>']`
- Labels: `botnet`, `<malware_family>`
- Score: 100, detection: true
- Valid 30 ngày từ timestamp

OpenCTI tự tạo `IPv4-Addr` observable + relationship `based-on`.

## Cấu trúc

```
v2-botnet/
├── Dockerfile
├── requirements.txt
└── src/
    ├── http_server.py          ← FastAPI server + background worker
    ├── connector.py            ← OpenCTI connector daemon (chế độ poll thư mục)
    ├── __main__.py             ← CLI dev/test tool
    ├── parsers/botnet.py       ← Parse JSON event → flat dict
    └── stix_builder/
        ├── indicator.py        ← Flat dict → STIX Indicator
        └── bundle.py           ← Gom indicators → STIX Bundle
```

## Config (environment variables)

| Variable | Default | Mô tả |
|----------|---------|-------|
| `OPENCTI_URL` | `http://localhost:8080` | URL OpenCTI |
| `OPENCTI_TOKEN` | — | API token (bắt buộc) |
| `PORT` | `8000` | Port HTTP server |
| `AUTH_TOKEN` | *(disabled)* | API key cho header `X-Api-Key` |
| `STORAGE_DIR` | `data/botnet` | Thư mục lưu file tạm |
| `MAX_FILE_SIZE` | `52428800` (50MB) | Giới hạn upload |
| `WATCH_DIR` | *(disabled)* | Thư mục watch tự động (dùng watchfiles) |

## Requirements

- Python 3.12
- OpenCTI >= 6.x, < 7
- `pycti[connector]>=6.0.0,<7`

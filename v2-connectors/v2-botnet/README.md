# v2-botnet — Botnet IOC Connector

Custom connector nhận file JSON botnet qua **HTTP API (FastAPI)**, parse thành STIX Indicator rồi push vào OpenCTI.

## Cách chạy (Two-Phase Push)

Có 2 luồng nhận file, đều dùng two-phase push:

**Luồng 1 — HTTP API (chính):**
```
1. POST /api/v1/files gửi JSON file → lưu vào storage_dir → enqueue
2. Worker nền xử lý ngay: parse → build bundle
3. Phase 1: Push entity bundles (Indicator) → RabbitMQ
4. Đợi 600s (10 phút) — chờ worker import hết entity
5. Phase 2: Push relationship bundles (nếu có)
6. Xóa file sau khi thành công, giữ lại nếu lỗi
```

**Luồng 2 — Poll thư mục (bổ sung):**
```
1. Connector daemon poll storage_dir mỗi 5 phút (PT5M)
2. Tìm file *.json chưa xử lý → parse → build bundle
3. Phase 1: Push entity bundles → đợi 600s → Phase 2: Push relationship bundles
4. Chạy liên tục, poll mỗi 5 phút
```

**Ví dụ:** Upload 1 file botnet.json chứa 500 event → Phase 1 gửi 1 entity bundle (500 Indicator) → đợi 600s → Phase 2 gửi relationship bundle → xóa file.

## API

```bash
# Upload file
curl -X POST http://localhost:20000/api/v1/files \
  -H "X-Api-Key: ChangeMe" \
  -F "file=@/ws/opencti/.data/sample/botnet.json"

# Qua Nginx (HTTPS) — self-signed cert, dùng -k để skip verify
curl -k -X POST https://localhost:21000/api/v1/files \
  -H "X-Api-Key: ChangeMe" \
  -F "file=@/workspace/tunv_opencti/.data/sample/botnet.json"

# Hoặc verify đúng cert
curl --cacert /path/to/nginx/certs/cert.pem \
  -X POST https://localhost:21000/api/v1/files \
  -H "X-Api-Key: ChangeMe" \
  -F "file=@botnet.json"
```

| Method | Path | Mô tả |
|--------|------|-------|
| `GET` | `/healthz` | Health check |
| `GET` | `/docs` | Swagger UI |
| `GET` | `/api/v1/config` | Xem config |
| `POST` | `/api/v1/files` | Upload JSON file |

## STIX Output

Mỗi event → 1 STIX `Indicator`:
- Pattern: `[ipv4-addr:value = '<source_ip>']`
- Labels: `botnet`, `<malware_family>`, score=100, valid 30 ngày
- OpenCTI tự tạo Observable + relationship `based-on`

## Cấu trúc

```
v2-botnet/
├── Dockerfile
├── requirements.txt
└── src/
    ├── http_server.py          ← FastAPI server + background worker
    ├── connector.py            ← OpenCTI connector daemon (poll thư mục)
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
| `CONNECTOR_DURATION_PERIOD` | `PT5M` | Poll thư mục mỗi 5 phút |
| `RELATIONSHIP_DELAY` | `600` | Giây đợi giữa Phase 1 và Phase 2 |
| `PORT` | `20000` | Port FastAPI (Nginx proxy 21000 → 20000) |
| `AUTH_TOKEN` | `ChangeMe` | API key cho header `X-Api-Key` |
| `STORAGE_DIR` | `data/botnet` | Thư mục lưu file tạm |
| `MAX_FILE_SIZE` | `52428800` (50MB) | Giới hạn upload |

## Reverse Proxy

- Nginx HTTPS tại `https://<host>:21000`
- Chỉ cho phép IP `163.223.58.10` và loopback (`127.0.0.1`, `::1`)
- Upload phải gửi header `X-Api-Key`

## Requirements

- Python 3.12, OpenCTI >= 6.x < 7, `pycti[connector]>=6.0.0,<7`

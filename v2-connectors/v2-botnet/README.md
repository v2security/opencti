# v2-botnet — Botnet IOC Connector

```
curl -k -X POST http://localhost:20000/api/v1/files \
  -H "X-Api-Key: ChangeMe" \
  -F "file=@/workspace/tunv_opencti/v2-connectors/.data/sample/botnet.json"

curl -k -X POST https://localhost:21000/api/v1/files \
  -H "X-Api-Key: ChangeMe" \
  -F "file=@/workspace/tunv_opencti/v2-connectors/.data/sample/botnet.json"

curl -k -X POST https://163.223.58.10:21000/api/v1/files \
  -H "X-Api-Key: ChangeMe" \
  -F "file=@/workspace/tunv_opencti/v2-connectors/.data/sample/botnet.json"
```

Lưu ý: request này chỉ thành công khi được gửi từ IP đã được allow trong Nginx, hiện tại là `163.223.58.10` và loopback của server (`127.0.0.1`, `::1`).

Custom connector nhận file JSON botnet qua **HTTP API (FastAPI)**, parse thành STIX Indicator rồi push vào OpenCTI.

## Luồng xử lý

```
POST /api/v1/files (JSON file)
    → Lưu vào storage_dir
  → Worker nền xử lý ngay sau khi file được enqueue
    → parse_file() → build_bundle() → STIX Bundle (Indicator × N)
    → send_stix2_bundle() ──publish──→ RabbitMQ
    → OpenCTI worker consume từ queue ──→ import vào OpenCTI
  → Xóa file sau khi xử lý thành công
  → Nếu push lỗi thì giữ file lại để retry
```

## API Endpoints

| Method | Path | Mô tả |
|--------|------|-------|
| `GET` | `/docs` | Swagger UI |
| `GET` | `/healthz` | Health check |
| `GET` | `/api/v1/config` | Xem config hiện tại |
| `POST` | `/api/v1/files` | Upload JSON file qua HTTPS, yêu cầu header `X-Api-Key` |

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
| `PORT` | `20000` | Port nội bộ của botnet app (Nginx proxy 21000 → 20000) |
| `AUTH_TOKEN` | `ChangeMe` | API key cho header `X-Api-Key` |
| `STORAGE_DIR` | `data/botnet` | Thư mục lưu file tạm |
| `MAX_FILE_SIZE` | `52428800` (50MB) | Giới hạn upload |
| `WATCH_DIR` | *(disabled)* | Thư mục watch tự động (dùng watchfiles) |

## Reverse Proxy

- Nginx publish HTTPS tại `https://<host>:21000`
- Chỉ cho phép IP `163.223.58.10` và loopback của chính server (`127.0.0.1`, `::1`) tại Nginx config
- Botnet app chỉ chạy nội bộ phía sau Nginx
- Upload request phải gửi header `X-Api-Key`
- Vì vậy máy client `163.223.58.10` gọi được, và chính server cũng có thể test qua `https://localhost:21000`; request đó vẫn phải gửi `X-Api-Key`
- Nếu server dùng self-signed hoặc CA nội bộ, phía client cần trust CA/public certificate đó; nếu server dùng certificate từ CA public thì không cần cung cấp cert riêng cho client

## Requirements

- Python 3.12
- OpenCTI >= 6.x, < 7
- `pycti[connector]>=6.0.0,<7`

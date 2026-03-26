# v2-nvd — NVD CVE Connector

Custom connector đồng bộ CVE từ NVD API 2.0 vào OpenCTI, bao gồm Vulnerability + Software (CPE) + Relationship + EPSS.

## Luồng xử lý

```
NVD API 2.0 ──fetch CVEs (phân trang, rate-limited)──→ Parse CVSS v2/v3.1/v4.0 + CWE + CPE
    → (Optional) Enrich EPSS từ api.first.org (batch 30 CVE/request)
    → Build STIX Bundle: Vulnerability + Software + Relationship(has)
    → send_stix2_bundle() ──publish──→ RabbitMQ
    → OpenCTI worker consume từ queue ──→ import/upsert vào OpenCTI
```

**Rate-limit:** 
+ NVD API cho phép 50 req/30s (có key) hoặc 5 req/30s (không key) — client tự sleep 0.6s (có key) / 6s (không) giữa mỗi request.
+ EPSS API gộp tối đa 100 CVE/request (default 30), delay 0.1s giữa các batch; gặp HTTP 429 → retry 3 lần với backoff 10s/20s/30s.

## 2 chế độ hoạt động

| Chế độ | Config | Mô tả |
|--------|--------|-------|
| **Incremental** | `NVD_MAINTAIN_DATA=true` (default) | Sync CVE thay đổi từ lần chạy trước |
| **Historical** | `NVD_PULL_HISTORY=true` | Import tất cả CVE từ `NVD_HISTORY_START_YEAR`, có resume |

`maintain_data: true` **(mặc định) — Incremental sync:**

+ Mỗi lần chạy, lấy CVE đã sửa đổi kể từ lần chạy trước → hiện tại
+ Lần đầu tiên: lấy CVE 24h gần nhất
+ Nhanh, chỉ lấy những gì mới

`pull_history: true` **— Historical import:**

+ Lấy **tất cả CVE** từ `history_start_year` (2019) đến hiện tại
+ Chia thành các window tối đa `max_date_range` (120 ngày) mỗi lần gọi API
+ Có resume: nếu bị crash giữa chừng, lần chạy sau sẽ tiếp tục từ chỗ dừng (lưu history_cursor trong state)
+ Từ 2019→2026 ≈ ~7 năm = ~21 window × hàng nghìn CVE mỗi window
+ Khi hoàn thành, cycle tiếp theo lại pull từ cursor đến hiện tại

## STIX Output

Mỗi CVE → 1 Bundle:
- `Vulnerability`: CVSS scores (v2 + v3.1 + v4.0), CWE, EPSS, external references
- `Software` × N: từ CPE match data (vendor, product, version)
- `Relationship` × N: Software → has → Vulnerability

## Cấu trúc

```
v2-nvd/
├── Dockerfile
├── requirements.txt
├── config.yml.sample
└── src/
    ├── __main__.py                 ← Entry point
    ├── connector.py                ← Main connector (schedule, sync logic)
    ├── config.py                   ← Config từ env/config.yml
    ├── utils.py                    ← Helpers (camel_to_snake, normalize_timestamp)
    ├── clients/
    │   ├── nvd.py                  ← NVD API client (paginate, rate-limit, retry)
    │   └── epss.py                 ← EPSS API client (batch query)
    ├── parsers/
    │   ├── cve.py                  ← Extract description, CWE
    │   ├── cpe.py                  ← Extract CPE matches từ configurations
    │   └── cvss.py                 ← Parse CVSS v2/v3.1/v4.0, sanitize v4 vector
    └── stix_builders/
        ├── vulnerability.py        ← CVE → STIX Vulnerability
        ├── software.py             ← CPE → STIX Software
        └── relationship.py         ← Software has Vulnerability
```

## Config (environment variables)

| Variable | Default | Mô tả |
|----------|---------|-------|
| `OPENCTI_URL` | — | URL OpenCTI (bắt buộc) |
| `OPENCTI_TOKEN` | — | API token (bắt buộc) |
| `CONNECTOR_ID` | — | UUID connector (bắt buộc) |
| `CONNECTOR_DURATION_PERIOD` | `PT6H` | Chu kỳ sync (ISO 8601) |
| `NVD_API_KEY` | *(built-in)* | NVD API key (khuyến nghị) |
| `NVD_MAINTAIN_DATA` | `true` | Bật incremental sync |
| `NVD_PULL_HISTORY` | `false` | Bật historical import |
| `NVD_HISTORY_START_YEAR` | `2019` | Năm bắt đầu (min 1999) |
| `EPSS_ENABLED` | `true` | Bật EPSS enrichment |

## Requirements

- Python 3.12
- OpenCTI >= 6.x, < 7
- `pycti[connector]>=6.0.0,<7`
- NVD API key (không có: 5 req/30s, có: 50 req/30s)

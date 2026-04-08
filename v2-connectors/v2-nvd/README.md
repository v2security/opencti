# v2-nvd — NVD CVE Connector

Custom connector đồng bộ CVE từ NVD API 2.0 vào OpenCTI, bao gồm Vulnerability + Software (CPE) + Relationship + EPSS.

## Cách chạy (Two-Phase Push)

Connector gửi bundle theo 2 pha để tránh race condition (worker xử lý relationship trước khi entity tồn tại):

```
1. Fetch CVEs từ NVD API (window tối đa 7 ngày, ~100-250 CVE/window)
2. Enrich EPSS (batch 30 CVE/request)
3. Phase 1: Push N entity bundles (Vulnerability + Software) → RabbitMQ
4. Đợi 600s (10 phút) — chờ worker import hết entity
5. Phase 2: Push N relationship bundles (Software → has → Vulnerability)
```

**Ví dụ thực tế:** Window 7 ngày → 99 CVE → Phase 1 gửi 99 entity bundles → đợi 600s → Phase 2 gửi 99 relationship bundles → xong.

## 2 chế độ

| Chế độ | Config | Chu kỳ | Mô tả |
|--------|--------|--------|-------|
| **Incremental** | `NVD_MAINTAIN_DATA=true` (default) | Đợi P1D (1 ngày) rồi chạy lại | Sync CVE thay đổi từ lần chạy trước. Lần đầu lấy 24h gần nhất. |
| **Historical** | `NVD_PULL_HISTORY=true` | **Chạy liên tục** cho đến khi hết, sau đó đợi P1D | Import từ `NVD_HISTORY_START_YEAR` đến nay, chia window 7 ngày, chạy window này → đợi 600s → window tiếp. Có resume nếu crash. |

**Historical:** Tất cả window chạy liên tục trong 1 cycle (chỉ nghỉ 600s giữa Phase 1 và Phase 2 mỗi window). Sau khi import hết lịch sử → đợi 1 ngày → chạy lại (lúc này chỉ có CVE mới).

`maintain_data: true`: Connector **không ghi file nào ra disk cả**. Toàn bộ dữ liệu (Vulnerability, Software, Relationship) được gửi thẳng vào OpenCTI qua `helper.send_stix2_bundle()`. State (timestamp lần chạy cuối) cũng lưu trong database OpenCTI qua `helper.get_state()`/`set_state()`, không phải file local.


## STIX Output

Mỗi CVE → 1 entity bundle + 1 relationship bundle:
- `Vulnerability`: CVSS v2/v3.1/v4.0, CWE, EPSS
- `Software` × N: từ CPE match
- `Relationship` × N: Software → has → Vulnerability

## Rate-limit

- NVD: 50 req/30s (có key) / 5 req/30s (không key)
- EPSS: batch 30 CVE/request, delay 0.1s, retry 3× nếu 429

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
| `CONNECTOR_DURATION_PERIOD` | `P1D` | Chu kỳ sync (1 ngày) |
| `RELATIONSHIP_DELAY` | `600` | Giây đợi giữa Phase 1 và Phase 2 |
| `NVD_API_KEY` | *(built-in)* | NVD API key (khuyến nghị) |
| `NVD_MAX_DATE_RANGE` | `7` | Max ngày mỗi API window |
| `NVD_MAINTAIN_DATA` | `true` | Bật incremental sync |
| `NVD_PULL_HISTORY` | `false` | Bật historical import (chạy liên tục) |
| `NVD_HISTORY_START_YEAR` | `2019` | Năm bắt đầu (min 1999) |
| `EPSS_ENABLED` | `true` | Bật EPSS enrichment |

## Requirements

- Python 3.12, OpenCTI >= 6.x < 7, `pycti[connector]>=6.0.0,<7`
- NVD API key (không có: 5 req/30s, có: 50 req/30s)

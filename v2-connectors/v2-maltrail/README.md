# v2-maltrail — Maltrail IOC Connector

Custom connector đồng bộ IOC (IP, Domain) từ [maltrail](https://github.com/stamparm/maltrail/) vào OpenCTI.

## Cách chạy (Two-Phase Push)

```
1. Clone repo maltrail mới, so sánh SHA256 với bản cũ → danh sách file thay đổi
2. Parse IOC từ file thay đổi (IP + Domain), gom theo batch 500
3. Phase 1: Push N entity bundles (Indicator + Observable) → RabbitMQ
4. Đợi 600s (10 phút) — chờ worker import hết entity
5. Phase 2: Push relationship bundles (Indicator → based-on → Observable)
6. Chu kỳ: 1 ngày (P1D) — xong rồi đợi 24h chạy lại
```

**Ví dụ thực tế:** Lần đầu chạy → ~12.000 entity bundles → đợi 600s → ~24 relationship bundles. Các lần sau chỉ sync file thay đổi → ít hơn nhiều.

## STIX Output

Mỗi IOC → 1 entity bundle + relationship bundle (gom theo batch):
- `Indicator`: pattern `[ipv4-addr:value = '...']` hoặc `[domain-name:value = '...']`
- `Observable`: IPv4-Addr hoặc Domain-Name
- `Relationship`: Indicator → based-on → Observable
- Labels: `v2 secure`, `maltrail`, `<category>` (malware=90, malicious=70, suspicious=50)
- Valid 30 ngày

## Cấu trúc

```
v2-maltrail/
├── Dockerfile
├── requirements.txt
├── config.yml.sample
└── src/
    ├── __main__.py                 ← Entry point
    ├── connector.py                ← Main connector (schedule, 4-step sync)
    ├── config.py                   ← Config từ env/config.yml
    ├── trail/
    │   ├── clone.py                ← Git clone + rotate old/new directories
    │   ├── compare.py              ← SHA256 diff old vs new .txt files
    │   └── parser.py               ← Parse .txt → IOC map (IP/domain)
    └── stix_builders/
        ├── indicator.py            ← IOC → STIX Indicator
        ├── observable.py           ← IOC → STIX Observable (IPv4/Domain)
        └── relationship.py         ← Indicator based-on Observable
```

## Config (environment variables)

| Variable | Default | Mô tả |
|----------|---------|-------|
| `OPENCTI_URL` | — | URL OpenCTI (bắt buộc) |
| `OPENCTI_TOKEN` | — | API token (bắt buộc) |
| `CONNECTOR_ID` | — | UUID connector (bắt buộc) |
| `CONNECTOR_DURATION_PERIOD` | `P1D` | Chu kỳ sync (mỗi ngày) |
| `RELATIONSHIP_DELAY` | `600` | Giây đợi giữa Phase 1 và Phase 2 |
| `MALTRAIL_DATA_DIR` | `tools/.data` | Thư mục lưu maltrail-old/maltrail-new |
| `MALTRAIL_REPO_URL` | `https://github.com/stamparm/maltrail.git` | Maltrail git repo |
| `MALTRAIL_BUNDLE_SIZE` | `500` | Số IOC mỗi bundle |
| `MALTRAIL_VALID_DAYS` | `30` | Số ngày indicator còn hiệu lực |

## Requirements

- Python 3.12, OpenCTI >= 6.x < 7, `pycti[connector]>=6.0.0,<7`
- `git` phải có trong PATH

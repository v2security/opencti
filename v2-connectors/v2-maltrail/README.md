# v2-maltrail — Maltrail IOC Connector

Custom connector đồng bộ IOC (IP, Domain) từ [maltrail](https://github.com/stamparm/maltrail/) vào OpenCTI.

Chạy mỗi ngày 1 lần, clone repo maltrail, so sánh thay đổi, parse IOC rồi tạo STIX Indicator push vào OpenCTI.

## Luồng xử lý

```
Step 1: Clone + Rotate
  rm maltrail-old/ → mv maltrail-new/ maltrail-old/ → git clone → maltrail-new/
  Dữ liệu lưu tại DATA_DIR (default: tools/.data)

Step 2: Compare (SHA256)
  For each .txt: size check → SHA256 hash → changed list

Step 3: Parse IOCs
  Changed files → clean lines (strip #, //, ports, CIDR) → map[value]label

Step 4: Create STIX Indicators + Observables
  IP  → Indicator [ipv4-addr:value = '...'] + IPv4-Addr Observable
  Domain → Indicator [domain-name:value = '...'] + Domain-Name Observable
  → send_stix2_bundle() ──publish──→ RabbitMQ
  → OpenCTI worker consume từ queue ──→ import vào OpenCTI
```

## STIX Output

Mỗi IOC → 1 STIX `Indicator` + 1 Observable + 1 Relationship (based-on):
- Pattern: `[ipv4-addr:value = '<ip>']` hoặc `[domain-name:value = '<domain>']`
- Labels: `v2 secure`, `maltrail`, `<category>` (malware/malicious/suspicious)
- Score: malware=90, malicious=70, suspicious=50
- Valid 30 ngày từ thời điểm sync

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
| `CONNECTOR_DURATION_PERIOD` | `P1D` | Chu kỳ sync (ISO 8601, mỗi ngày) |
| `MALTRAIL_DATA_DIR` | `tools/.data` | Thư mục lưu maltrail-old/maltrail-new |
| `MALTRAIL_REPO_URL` | `https://github.com/stamparm/maltrail.git` | Maltrail git repo |
| `MALTRAIL_BUNDLE_SIZE` | `500` | Số IOC mỗi bundle gửi OpenCTI |
| `MALTRAIL_VALID_DAYS` | `30` | Số ngày indicator còn hiệu lực |

## Requirements

- Python 3.12
- OpenCTI >= 6.x, < 7
- `pycti[connector]>=6.0.0,<7`
- `git` phải có trong PATH

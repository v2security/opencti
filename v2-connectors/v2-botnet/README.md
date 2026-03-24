# source-botnet-sync

Nhận file JSON botnet → parse → tạo STIX Indicator → push vào OpenCTI.

---

## Cấu trúc thư mục

```
tools/source-botnet-sync/
├── README.md
└── src/
    ├── parsers/
    │   └── botnet.py          ← Layer 1: parse raw JSON → flat dict
    ├── stix_builder/
    │   └── indicator.py       ← Layer 2: flat dict → STIX Indicator object
    ├── http_server.py         ← Entry point A: nhận file qua HTTP
    ├── connector.py           ← Entry point B: OpenCTI connector daemon
    ├── __main__.py            ← Entry point C: dry-run / test local
    └── __push__.py            ← Entry point D: push trực tiếp lên OpenCTI

```

---

## Cấu trúc file JSON đầu vào

```json
{
    "events": [
        {
            "id": "1f11b981-cef9-621d-9277-42010a960003",
            "timestamp": "2026-03-09T09:12:35.963Z",
            "type": "EVENT_TYPE_HTTP",
            "malware": {
                "family": "andromeda",
                "variant": "gamarue"
            },
            "source": {
                "ip": "171.245.56.97",
                "port": 59177,
                "asn": 7552,
                "isp": "Viettel Group",
                "country_iso": "VN",
                "city": "Hanoi",
                "autonomous_system_name": ""
            },
            "destination": {
                "port": 80
            },
            "token": "...",
            "victim": { "summary": "171.245.56.97:59177" },
            "asset_ids": []
        }
    ],
    "page_count": "20",
    "total_events": "20",
    "next_page_token": "..."
}
```

---

## STIX Bundle output

```
Bundle
├── Identity        ("Krytoslogic Telltale")
└── Indicator ×N    (1 indicator / 1 event)
```

OpenCTI tự động tạo `IPv4-Addr` observable và relationship `based-on` từ `pattern` + `x_opencti_main_observable_type` — không cần tạo thủ công.

---

## Mapping JSON botnet → STIX Indicator

### Fields tiêu chuẩn STIX

| Field nguồn | STIX field | Giá trị |
|---|---|---|
| `source.ip` | `pattern` | `[ipv4-addr:value = '<ip>']` |
| `timestamp` | `valid_from` | ISO 8601 |
| `timestamp` | `created` | ISO 8601 |
| `timestamp` | `modified` | ISO 8601 |
| `timestamp` + 30 ngày | `valid_until` | ISO 8601 — dùng cho decay |
| `malware.family` + `source.ip` | `name` | `"[andromeda] 171.245.56.97"` |
| `id` | `external_references[].external_id` | event UUID gốc |
| `malware.family` | `labels` | `["botnet", "andromeda"]` |
| — | `indicator_types` | `["malicious-activity"]` (cố định) |
| — | `pattern_type` | `"stix"` (cố định) |
| — | `confidence` | `100` (cố định) |
| — | `revoked` | `false` (cố định) |
| — | `created_by_ref` | Identity "Krytoslogic Telltale" |

### Fields mô tả (computed)

| Field | Giá trị |
|---|---|
| `description` | `[andromeda/gamarue] infected host 171.245.56.97 observed via EVENT_TYPE_HTTP` `\nfrom VN/Hanoi (ISP: Viettel Group, ASN: 7552)` |

### OpenCTI custom fields (`x_opencti_*`)

| Field nguồn | OpenCTI field | Kiểu |
|---|---|---|
| — | `x_opencti_score` | `100` (cố định) |
| — | `x_opencti_main_observable_type` | `"IPv4-Addr"` (cố định) |
| — | `x_opencti_detection` | `true` (cố định) — bật detection rule |
| `type` | `x_opencti_event_type` | string |
| `malware.family` | `x_opencti_malware_family` | string |
| `malware.variant` | `x_opencti_malware_variant` | string |
| `source.port` | `x_opencti_source_port` | int |
| `source.asn` | `x_opencti_asn` | int |
| `source.isp` | `x_opencti_isp` | string |
| `source.country_iso` | `x_opencti_country` | string |
| `source.city` | `x_opencti_city` | string |
| `destination.port` | `x_opencti_dst_port` | int |

### Không map

| Field | Lý do |
|---|---|
| `source.autonomous_system_name` | Luôn rỗng trong data |
| `token` | Internal auth token |
| `victim.summary` | Trùng `source.ip:source.port` |
| `asset_ids` | Luôn rỗng |
| `page_count`, `total_events`, `next_page_token` | Metadata wrapper |

### Fields do OpenCTI server tự quản lý (không cần set)

| Field | Ý nghĩa |
|---|---|
| `decay_base_score`, `decay_applied_rule`, `decay_history`, `decay_next_reaction_date` | Server tự tính từ `x_opencti_score` + decay rule |
| `rel_created-by`, `rel_based-on`, `rel_object-label` | Server tự tạo relationship khi ingest |
| `internal_id`, `standard_id`, `creator_id`, `created_at`, `updated_at` | Server-side metadata |
| `i_attributes` | Audit log — server tự ghi |

**Quy tắc bỏ qua:** field không được thêm vào kwargs nếu giá trị là `None`, `""`, hoặc không tồn tại.

### Ghi chú về `valid_until` và decay

OpenCTI có cơ chế **decay** tự động giảm `x_opencti_score` theo thời gian. Nếu không set `valid_until`, indicator sẽ tồn tại mãi mãi mà không bao giờ expire.

- Botnet IP thường không sống lâu → set `valid_until = timestamp + 30 ngày`
- OpenCTI sẽ tự chạy decay rule: score giảm dần từ 100 → revoke khi xuống ngưỡng thấp
- Có thể thay đổi số ngày trong config (`VALID_UNTIL_DAYS`, mặc định `30`)

---

## Parser Design (theo pattern nvd-sync)

Tổ chức giống `parsers/cvss.py`: **getter → builder**, `stix_builder/indicator.py` gọi từng builder và `.update()` vào kwargs — giống `vulnerability.py`.

### Tầng 1 — Getters (`parsers/botnet.py`)

```python
get_malware(event)      → event.get("malware") or {}       # {"family", "variant"}
get_source(event)       → event.get("source") or {}        # {"ip", "port", "asn", ...}
get_destination(event)  → event.get("destination") or {}   # {"port"}
```

### Tầng 2 — Builders (`parsers/botnet.py`)

Mỗi builder nhận sub-dict, trả về `partial dict` dùng trong `parse_event()`:

| Builder | Input keys | Output keys |
|---|---|---|
| `build_malware_props(malware)` | `family`, `variant` | `malware_family`, `malware_variant` |
| `build_source_props(source)` | `ip`, `port`, `asn`, `isp`, `country_iso`, `city` | `source_ip`, `source_port`, `source_asn`, `source_isp`, `country_iso`, `city` |
| `build_destination_props(destination)` | `port`, `ip` | `destination_port`, `destination_ip` |

### Tầng 3 — Builders (`stix_builder/indicator.py`)

Nhận flat dict từ `parse_event()`, trả về `partial kwargs` cho Indicator:

| Builder | Output kwargs |
|---|---|
| `build_malware_props(parsed)` | `x_opencti_malware_family`, `x_opencti_malware_variant` |
| `build_source_props(parsed)` | `x_opencti_source_port`, `x_opencti_asn`, `x_opencti_isp`, `x_opencti_country`, `x_opencti_city` |
| `build_destination_props(parsed)` | `x_opencti_dst_port`, `x_opencti_dst_ip` |
| `build_description(parsed)` | `str` — human-readable description |
| `build_valid_until(timestamp, days=30)` | `str` — ISO 8601, timestamp + N ngày |

### Flow parse

```
events[] trong JSON
      │
      ▼
parse_event(raw)
  ├── get_malware()  → build_malware_props()
  ├── get_source()   → build_source_props()
  └── get_destination() → build_destination_props()
      │
      ▼ flat dict
create_indicator(parsed)
  ├── build_description()
  ├── build_malware_props()   → kwargs.update()
  ├── build_source_props()    → kwargs.update()
  └── build_destination_props() → kwargs.update()
      │
      ▼
Indicator(allow_custom=True)
```

---

```
conda activate opencti
```

```
POST /api/v1/files
      │
      ▼
 save file → _file_queue.put(path) → return 202 {"status": "queued"}
                       │
              [botnet-worker thread]
                       │
                       ▼
              parse_file(path) → create_indicator() × N
                       │
                       ▼
              Bundle → client.stix2.import_bundle_from_json()
                       │
              ┌────────┴────────┐
           success            error
              │                  │
         path.unlink()      keep file
         log "deleted"      log "keeping for retry"
```



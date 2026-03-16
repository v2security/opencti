# IOC ES→MySQL Sync Tool

Đồng bộ IOC đã xác nhận (IP / Domain / Hash) từ OpenCTI (Elasticsearch, STIX 2.1) sang MySQL (`ids_blacklist`, `hashlist`).

## Architecture

```
┌─────────────┐     pycti       ┌────────────┐
│  OpenCTI    │ ◄────────────── │  client.py │  query N items, cursor = updated_at
│  (ES index) │   GraphQL API   └─────┬──────┘
└─────────────┘                       │ list[dict]  (max max_item_query)
                                      ▼
                               ┌──────────────┐
                               │transformer.py│ ← enrichment.py (GeoIP / VT pass)
                               │              │   same version for whole batch
                               └──────┬───────┘
                                      │ list[dict]  row dicts
                                      ▼
                               ┌──────────────┐
                               │ database.py  │ → UPSERT ids_blacklist
                               │              │ → UPSERT hashlist
                               │              │ → get_last_version() for resume
                               └──────────────┘
```

## File Structure

```
tools/ioc-es2mysql/
├── .env              # Secrets: API token, MySQL password, VT key
├── config.yaml       # Tất cả config (${VAR} tham chiếu .env)
├── requirements.txt
├── Makefile          # Build targets (make build)
├── deploy/           # ← Build output + systemd
│   ├── v2-ioc-blacklist-sync          # Binary (built by make)
│   ├── v2-ioc-hashlist-sync           # Binary (built by make)
│   ├── v2-ioc-blacklist-sync.service  # Systemd service
│   └── v2-ioc-hashlist-sync.service   # Systemd service
├── ids_blacklist_sync/
│   └── main.py       # Entry point — blacklist sync
├── hashlist_sync/
│   └── main.py       # Entry point — hashlist sync
└── util/
    ├── config.py     # Load YAML + resolve ${VAR}
    ├── utils.py      # Logger
    ├── client.py     # Query OpenCTI qua pycti
    ├── enrichment.py # GeoIP (ip-api.com) + VirusTotal
    ├── transformer.py# STIX observable → MySQL row dict
    ├── database.py   # MySQL pool + UPSERT + get_last_version()
    └── scheduler.py  # Cursor-based sync loop
```

## Logic chính

### 1. Filter — "Confirmed IOC"

Chỉ lấy observable thỏa **cả hai** điều kiện:

- **`x_opencti_score >= 70`** — scoring riêng của OpenCTI
- **`confidence >= 70`** — trường confidence theo chuẩn STIX 2.1

Cả hai ngưỡng cấu hình trong `config.yaml → opencti.min_score / min_confidence`.

### 2. Sync loop — Cursor-based drain

1. **Khởi động**: cursor = MAX(config `time_start_sync`, MAX(version) trong MySQL)
2. **Mỗi batch**: query tối đa 20 observable, sắp xếp `updated_at ASC`
3. **Có data (N > 0)**: transform → enrich → UPSERT → đẩy cursor → **loop ngay** (không sleep)
4. **Hết data (N = 0)**: **sleep 60s** rồi query lại
5. **Crash recovery**: restart → đọc `MAX(version)` từ MySQL → resume, overlap 5s tránh gap, UPSERT tránh trùng

### 3. Transform IP / Domain → `ids_blacklist`

- `entity_type` → `stype`: IPv4-Addr/IPv6-Addr → `ip`, Domain-Name → `domain`
- `observable_value` → `value`
- **GeoIP**: gọi `ip-api.com` cho cả IP lẫn domain (không cần DNS resolve) → `country` format `Country-CountryCode` (vd: `United States-US`, `Japan-JP`). Không resolve được → `none`
- `createdBy.name` → `source` (fallback: `suspicious`)
- Tất cả rows trong 1 batch cùng `version` (YYYYMMDDHHmmss)

### 4. Transform Hash → `hashlist`

- Lấy **tất cả** hash từ `hashes[]` — mỗi hash 1 row (MD5, SHA-1, SHA-256, SHA-512)
- Observable chỉ có filename mà không có hash → **bỏ qua**
- VirusTotal: có API key → query VT lấy `description`/`name`; không có key → `unknown`/`unknown`

### 5. Tại sao batch 20?

- **Rate limit**: ip-api.com giới hạn 45 req/phút, batch nhỏ tránh bị block
- **Crash resilience**: mất tối đa 20 item nếu crash, cursor lưu sau mỗi batch

## Build & Deploy

```bash
# 1. Install dependencies
make install

# 2. Build binaries → deploy/
make build
# Output: deploy/v2-ioc-blacklist-sync, deploy/v2-ioc-hashlist-sync
```

Sau khi build, folder `deploy/` chứa tất cả file cần thiết để deploy:

```
deploy/
├── v2-ioc-blacklist-sync          # Binary
├── v2-ioc-hashlist-sync           # Binary
├── v2-ioc-blacklist-sync.service  # Systemd
└── v2-ioc-hashlist-sync.service   # Systemd
```

### Deploy lên server

```bash
# Copy binary + config
cp deploy/v2-ioc-blacklist-sync deploy/v2-ioc-hashlist-sync /opt/tools/
cp config.yaml GeoLite2-Country.mmdb /opt/tools/

# Copy systemd + enable
cp deploy/*.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now v2-ioc-blacklist-sync
systemctl enable --now v2-ioc-hashlist-sync
```

### Run manual (test)

```bash
cd /opt/tools
./v2-ioc-blacklist-sync          # chạy liên tục
./v2-ioc-blacklist-sync --once   # chạy 1 lần rồi thoát
./v2-ioc-hashlist-sync           # chạy liên tục
./v2-ioc-hashlist-sync --once    # chạy 1 lần rồi thoát
```

### Check logs

```bash
systemctl status v2-ioc-blacklist-sync
journalctl -u v2-ioc-blacklist-sync -f
journalctl -u v2-ioc-hashlist-sync -f
```

Cả hai service chạy liên tục (`Type=simple`), tự động restart nếu crash (`Restart=on-failure`, delay 30s).
Env đọc từ `/etc/saids/opencti/.env`.

### Makefile Targets

| Target           | Description                          |
|------------------|--------------------------------------|
| `make install`   | Install Python dependencies          |
| `make build`     | Build both binaries                  |
| `make build-blacklist` | Build `v2-ioc-blacklist-sync` only |
| `make build-hashlist`  | Build `v2-ioc-hashlist-sync` only  |
| `make clean`     | Remove build artifacts               |
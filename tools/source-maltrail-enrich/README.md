# source-maltrail-sync — Maltrail IOC Enrich

Daily sync from [maltrail](https://github.com/stamparm/maltrail/) → MySQL `ids_blacklist`.

## Project Structure

```
source-maltrail-sync/
├── main.go                         # Entry point — orchestrate 4 steps
├── Makefile                        # Build target (make build)
├── internal/
│   ├── config/
│   │   └── config.go               # Load .env, validate env vars
│   ├── trail/
│   │   ├── clone.go                # Git clone --depth 1, rotate old/new
│   │   ├── compare.go              # SHA256 diff old vs new .txt files
│   │   ├── parser.go               # Parse .txt → IOC map (IP/domain)
│   │   └── fs.go                   # Filesystem helpers
│   └── store/
│       └── mysql.go                # Batch UPDATE ids_blacklist
├── .env.sample                    # Config template
├── go.mod / go.sum
└── deploy/                         # ← Build output + systemd
    ├── v2-ioc-maltrail-sync        # Binary (built by make)
    ├── v2-ioc-maltrail-sync.service
    └── v2-ioc-maltrail-sync.timer
```

## Flow

```
Step 1: Clone + Rotate
  rm maltrail-old/ → mv maltrail-new/ maltrail-old/ → git clone → maltrail-new/

Step 2: Compare (SHA256)
  For each .txt: size check → SHA256 hash → changed list

Step 3: Parse IOCs
  Changed files → clean lines (strip #, //, ports, CIDR) → map[value]label

Step 4: Update MySQL
  UPDATE ids_blacklist SET source = ? WHERE value IN (...) AND source = 'suspicious'
  Batch size: 500
```

## Build & Deploy

```bash
# 1. Config
cp .env.sample .env
vi .env   # fill MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE

# 2. Build → deploy/
make build
# Output: deploy/v2-ioc-maltrail-sync

# 3. Test
deploy/v2-ioc-maltrail-sync
```

Sau khi build, folder `deploy/` chứa tất cả:

```
deploy/
├── v2-ioc-maltrail-sync          # Binary
├── v2-ioc-maltrail-sync.service  # Systemd service
└── v2-ioc-maltrail-sync.timer    # Systemd timer
```

### Deploy lên server

```bash
# Copy binary
cp deploy/v2-ioc-maltrail-sync /opt/tools/

# Copy systemd + enable
cp deploy/v2-ioc-maltrail-sync.service deploy/v2-ioc-maltrail-sync.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now v2-ioc-maltrail-sync.timer
```

### Check

```bash
systemctl list-timers v2-ioc-maltrail-sync.timer
journalctl -u v2-ioc-maltrail-sync -f
```

Service chạy oneshot qua timer (mỗi ngày 03:00). Env đọc từ `/etc/saids/opencti/.env`.

# source-maltrail — Maltrail IOC Sync

Daily sync from [maltrail](https://github.com/stamparm/maltrail/) → MySQL `ids_blacklist`.

## Project Structure

```
source-maltrail/
├── cmd/
│   └── maltrail-sync/
│       └── main.go                 # Entry point — orchestrate 4 steps
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
├── .env.example                    # Config template
├── go.mod / go.sum
├── maltrail-sync.service           # Systemd service
└── maltrail-sync.timer             # Systemd timer (daily 03:00)
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

## Setup

```bash
# 1. Config
cp .env.example .env
vi .env   # fill MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE

# 2. Build
go build -o maltrail-sync .

# 3. Test
./maltrail-sync

# 4. Deploy + systemd timer
cp maltrail-sync /opt/tools/
cp .env /opt/tools/
cp maltrail-sync.service maltrail-sync.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now maltrail-sync.timer

# Check
systemctl list-timers maltrail-sync.timer
journalctl -u maltrail-sync -f
```

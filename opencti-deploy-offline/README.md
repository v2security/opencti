# OpenCTI Offline Deployment — Rocky Linux 9

Deploy OpenCTI 6.9.22 trên Rocky Linux 9 **không cần internet** trên máy target.

---

## PHẦN 1: MÁY BUILD (có internet)

### Bước 1: Clean (nếu cần build lại)

```bash
cd opencti-deploy-offline

# Hỏi từng component muốn xóa
./v2_clean_build.sh

# Hoặc xóa tất cả
./v2_clean_build.sh --all
```

### Bước 2: Chuẩn bị binaries (chạy 1 lần duy nhất)

```bash
# Build Python 3.12 runtime → runtime/python312.tar.gz
cd runtime && bash v2-build-python.sh

# Package Node.js 22 → runtime/nodejs22.tar.gz
cd runtime && bash v2-build-nodejs.sh

# Đảm bảo có sẵn:
#   rpms/*.rpm (~126 files)
#   minio/minio, minio/mc
#   rabbitmq/rabbitmq-server-generic-unix-*.tar.xz
```

### Bước 3: Build + Prepare

```bash
cd opencti-deploy-offline

# 2.1 Build backend (yarn install + build:prod)
./opencti/v2_build_backend.sh

# 2.2 Build frontend (React + Relay)
./opencti/v2_build_frontend.sh

# 2.3 Prepare platform (copy source + download pip packages)
./opencti/v2_prepare_opencti.sh

# 2.4 Prepare worker (copy source + download pip packages)
./opencti-worker/v2_prepare_opencti_worker.sh
```

### Bước 4: Pack

```bash
cd opencti-deploy-offline

# → opencti-offline-deploy.tar.gz (~800MB-1.2GB)
./v2_pack_opencti.sh
```

### Bước 5: Copy sang máy target

```bash
scp opencti-offline-deploy.tar.gz root@163.223.58.17:/opt/
```

---

## PHẦN 2: MÁY TARGET (Rocky Linux 9, offline)

### Yêu cầu

- Rocky Linux 9.x
- Elasticsearch 8.x đã cài + chạy (port 8686)
- RAM ≥ 8GB, Disk ≥ 50GB
- `sysctl -w vm.max_map_count=262144`

### Bước 1: Giải nén + đặt files vào đúng chỗ

```bash
cd /opt
tar xzf opencti-offline-deploy.tar.gz
bash v2_unpack_opencti.sh
```

Script copy files vào đúng path cuối cùng, **xóa folder tạm** sau khi xong.
Còn lại sau unpack: `rpms/` + `runtime/` + `rabbitmq/` (cần cho setup).

Kết quả sau khi chạy xong:

| Nguồn | Đích |
|-------|------|
| `minio/minio`, `minio/mc` | `/usr/local/bin/` |
| `minio/v2_*.sh` | `/usr/local/bin/` |
| `rabbitmq/v2_start/stop/uninstall_rabbitmq.sh` | `/usr/local/bin/` |
| `runtime/v2_uninstall_*.sh` | `/usr/local/bin/` |
| `config/*` | `/etc/redis/`, `/etc/minio/`, `/etc/rabbitmq/`, `/etc/logrotate.d/` |
| `systemd/*.service` | `/etc/systemd/system/` |
| `.env` | `/etc/saids/opencti/.env` |
| `opencti/*` | `/etc/saids/opencti/` |
| `opencti/v2_*.sh` | `/usr/local/bin/` |
| `opencti-worker/*` | `/etc/saids/opencti-worker/` |
| `opencti-worker/v2_*.sh` | `/usr/local/bin/` |
| `v2_ti_uninstall.sh` | `/usr/local/bin/` |

### Bước 2: Cài RPMs

```bash
cd /opt/rpms
bash v2_install_rpms.sh
```

### Bước 3: Cài Python 3.12 + Node.js 22

```bash
cd /opt/runtime
bash v2_install_python.sh     # → /opt/python312/
bash v2_install_nodejs.sh      # → /opt/nodejs/
```

### Bước 4: Setup MinIO

```bash
v2_setup_minio.sh
```

### Bước 5: Setup RabbitMQ

```bash
cd /opt/rabbitmq
bash v2_setup_rabbitmq.sh
```

### Bước 6: Start infrastructure

```bash
systemctl enable --now redis minio rabbitmq
systemctl status redis minio rabbitmq
```

### Bước 7: Setup OpenCTI Platform (Python venv)

```bash
v2_setup_opencti.sh
```

### Bước 8: Setup OpenCTI Worker (Python venv)

```bash
v2_setup_opencti_worker.sh
```

### Bước 9: Sửa credentials ⚠️

File `.env` là **config tập trung duy nhất** cho Platform, Worker và Tools.
Start scripts tự đọc file này và map sang format riêng của từng component.

```bash
vi /etc/saids/opencti/.env
```

**Các biến cần sửa:**

| Biến | Mô tả | Default |
|------|--------|---------|
| `APP_ADMIN_EMAIL` | Admin email | `admin@v2secure.vn` |
| `APP_ADMIN_PASSWORD` | Admin password | `changeme` |
| `APP_ADMIN_TOKEN` | API token (UUID) | `changeme-uuid` |
| `APP_BASE_URL` | URL truy cập | `http://localhost:8080` |
| `REDIS_PASSWORD` | Redis password | `changeme` |
| `ELASTICSEARCH_URL` | ES endpoint | `http://localhost:8686` |
| `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY` | MinIO credentials | `opencti` / `changeme` |
| `RABBITMQ_USERNAME` / `RABBITMQ_PASSWORD` | RabbitMQ credentials | `opencti` / `changeme` |
| `MYSQL_PASSWORD` | MySQL password (tools) | `changeme` |
| `AI_TOKEN` | Anthropic API key | *(optional)* |
| `TOOL_DATA_DIR` | Thư mục data cho tools | `/opt/tools/data` |
| `VIRUSTOTAL_API_KEY` | VirusTotal API key | *(optional)* |

### Bước 10: Start OpenCTI

```bash
# Platform
systemctl enable --now opencti-platform
systemctl status opencti-platform

# Đợi khởi tạo xong...

# Workers
systemctl enable opencti-worker@{1..3}
systemctl start opencti-worker@1 opencti-worker@2 opencti-worker@3

systemctl status opencti-worker@1 opencti-worker@2 opencti-worker@3
```

### Bước 11: Kiểm tra

```bash
curl -i http://localhost:8080/
# → 200
```

---

## Quản lý services

### Stop

```bash
# Từng cái
systemctl stop opencti-worker@1 opencti-worker@2 opencti-worker@3
systemctl stop opencti-platform
systemctl stop rabbitmq minio redis

# Xem status
systemctl status opencti-platform opencti-worker@{1..3}
```

### Start lại

```bash
systemctl start redis minio rabbitmq
systemctl start opencti-platform
# Đợi ~60s...
systemctl start opencti-worker@1 opencti-worker@2 opencti-worker@3
```

### Gỡ bỏ toàn bộ

```bash
v2_ti_uninstall.sh

# Hoặc giữ data
KEEP_DATA=true v2_ti_uninstall.sh
```

### Xem logs

```bash
journalctl -u opencti-platform -f
tail -f /var/log/opencti/opencti-platform.log
tail -f /var/log/opencti-worker/opencti-worker-1.log
```

### Reset setup (chạy lại)

```bash
rm /var/lib/.v2_setup_opencti_done         # Platform
rm /var/lib/.v2_setup_opencti_worker_done  # Worker
```

---

## Cấu trúc thư mục

### Trên máy build

```
opencti-deploy-offline/
├── v2_clean_build.sh             ★ Xóa artifacts để build lại (máy build)
├── v2_pack_opencti.sh            ★ Đóng gói → archive
├── v2_unpack_opencti.sh          ★ Đặt files vào đúng chỗ (máy target)
├── v2_ti_uninstall.sh            ★ Gỡ bỏ toàn bộ → /usr/local/bin/
│
├── rpms/
│   ├── v2_install_rpms.sh
│   └── *.rpm                     ~126 packages
│
├── runtime/
│   ├── v2_install_python.sh      → /opt/python312/
│   ├── v2_install_nodejs.sh      → /opt/nodejs/
│   ├── v2_uninstall_python.sh
│   ├── v2_uninstall_nodejs.sh
│   ├── python312.tar.gz
│   └── nodejs22.tar.gz
│
├── minio/
│   ├── minio, mc                 Binaries
│   ├── v2_setup_minio.sh         First-boot setup
│   ├── v2_start_minio.sh         Systemd gọi
│   ├── v2_stop_minio.sh
│   └── v2_uninstall_minio.sh
│
├── rabbitmq/
│   ├── rabbitmq-server-*.tar.xz
│   ├── v2_setup_rabbitmq.sh      First-boot setup
│   ├── v2_start_rabbitmq.sh      Systemd gọi
│   ├── v2_stop_rabbitmq.sh
│   └── v2_uninstall_rabbitmq.sh
│
├── config/                       Tất cả config files
├── systemd/                      4 service units
│
├── opencti/                      Platform (máy build)
│   ├── v2_build_backend.sh       Build: yarn build:prod
│   ├── v2_build_frontend.sh      Build: React + Relay
│   ├── v2_prepare_opencti.sh     Prepare: copy source + pip
│   ├── v2_setup_opencti.sh       Setup: create venv (máy target)
│   ├── v2_start_opencti.sh       Start: env vars + npm (⚠️ secrets)
│   ├── v2_stop_opencti.sh
│   └── v2_uninstall_opencti.sh
│
└── opencti-worker/               Worker (máy build)
    ├── v2_prepare_opencti_worker.sh
    ├── v2_setup_opencti_worker.sh
    ├── v2_start_opencti_worker.sh (⚠️ secrets)
    ├── v2_stop_opencti_worker.sh
    └── v2_uninstall_opencti_worker.sh
```

### Trên máy target (sau unpack + setup)

```
/opt/python312/                → Python 3.12
/opt/nodejs/                   → Node.js 22
/opt/rabbitmq/                 → RabbitMQ server
/usr/local/bin/minio           → MinIO binary
/usr/local/bin/v2_*.sh         → Tất cả scripts (setup/start/stop/uninstall)
/usr/local/bin/v2_ti_uninstall.sh → Gỡ toàn bộ stack
/usr/bin/redis-server          → Redis (RPM)

/etc/saids/opencti/            ★ Platform
/etc/saids/opencti-worker/     ★ Workers

/etc/redis/  /etc/minio/  /etc/rabbitmq/   → Configs
/etc/systemd/system/                       → Service units

/var/log/opencti/              → Platform logs
/var/log/opencti-worker/       → Worker logs

Ports:
  6379   Redis
  8686   Elasticsearch
  9000   MinIO API
  9001   MinIO Console
  5672   RabbitMQ AMQP
  15672  RabbitMQ Management
  8080   OpenCTI Platform
```

---

## Troubleshooting

| Vấn đề | Giải pháp |
|--------|-----------|
| Platform SEGV (signal 11) | EQL patch đã tự động áp dụng. Kiểm tra `check_indicator.py` |
| Không connect ES | Sửa `ELASTICSEARCH__URL` trong `/usr/local/bin/v2_start_opencti.sh` |
| Worker không connect platform | Kiểm tra `OPENCTI_URL` + `OPENCTI_TOKEN` |
| Setup chạy lại | `rm /var/lib/.v2_setup_*_done` |

---

## Docker Test

```bash
# Prepare trên host
cd opencti && ./v2_build_backend.sh && ./v2_build_frontend.sh && ./v2_prepare_opencti.sh
cd opencti-worker && ./v2_prepare_opencti_worker.sh

# Start test
make start && make exec

# Trong container — chạy từng bước
cd /tmp/rpms && bash v2_install_rpms.sh
cd /tmp/runtime && bash v2_install_python.sh && bash v2_install_nodejs.sh
v2_setup_minio.sh
cd /tmp/rabbitmq && bash v2_setup_rabbitmq.sh
systemctl enable --now redis minio rabbitmq
v2_setup_opencti.sh
v2_setup_opencti_worker.sh
systemctl enable --now opencti-platform
# Đợi 60s...
systemctl enable opencti-worker@{1..3}
systemctl start opencti-worker@1 opencti-worker@2 opencti-worker@3
```

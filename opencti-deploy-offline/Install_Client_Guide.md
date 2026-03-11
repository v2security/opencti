# OpenCTI 6.9.22 — Hướng dẫn cài đặt Offline

> **Target OS:** Rocky Linux 9 (minimal install)
> **Yêu cầu:** root access, không cần internet trên máy đích

---

## Tổng quan

Hệ thống gồm 2 package, build trên máy có internet, copy sang máy offline:

| Package | File | Size | Chứa |
|---------|------|------|------|
| **Infra** | `opencti-infra-package.tar.gz` | ~200M | Redis 6.2 (RPM), MinIO, RabbitMQ 4.2, Erlang 27, RPMs, configs, SSL cert |
| **App** | `opencti-app-package.tar.gz` | ~430M | Python 3.12, Node.js 22, OpenCTI Platform + Frontend, Worker, pip packages |

**Elasticsearch 8.x** cài riêng (không nằm trong package).

---

## Step 1: Build trên máy có internet

### 1.1 Yêu cầu máy build

- Rocky Linux 8/9 hoặc tương đương (x86_64)
- Docker (cho build Python runtime)
- Node.js ≥ 20, gcc, gcc-c++, make
- Git clone repo OpenCTI

### 1.2 Build packages

```bash
cd opencti-deploy-offline

# Generate SSL certificate (nếu chưa có)
bash scripts/gen-ssl-cert.sh

# Pack infrastructure
make pack-infra
# → files/opencti-infra-package.tar.gz (~200M)

# Pack application (mất ~8-10 phút)
make pack-app
# → files/opencti-app-package.tar.gz (~430M)
```

---

## Step 2: Copy sang máy offline

### 2.1 SCP files

```bash
# Từ máy build → máy offline
scp files/opencti-infra-package.tar.gz  root@163.223.58.17:/root/
scp files/opencti-app-package.tar.gz    root@163.223.58.17:/root/
```

> **Lưu ý:** SSL cert (`opencti.key`, `opencti.crt`) đã nằm sẵn trong `opencti-infra-package.tar.gz`, không cần copy riêng.

### 2.2 Extract trên máy offline

```bash
# SSH vào máy offline
ssh root@163.223.58.17

# Tạo thư mục deploy
mkdir -p /root/opencti-deploy

# Extract infrastructure package (bao gồm cả cert/)
tar -xzf /root/opencti-infra-package.tar.gz -C /root/opencti-deploy

# Copy app package vào đúng chỗ
cp /root/opencti-app-package.tar.gz /root/opencti-deploy/files/
```

Sau khi extract, cấu trúc sẽ là:
```
/root/opencti-deploy/
├── files/
│   ├── minio                               # MinIO binary
│   ├── mc                                   # MinIO client
│   ├── rabbitmq-server-generic-unix-4.2.0.tar.xz
│   └── opencti-app-package.tar.gz           # (copy riêng)
├── rpm/                                     # ~106 RPM packages (bao gồm redis-*.rpm)
├── scripts/
│   ├── setup_infra.sh                       # ← CHẠY TRƯỚC
│   ├── setup_app.sh                         # ← CHẠY SAU
│   ├── enable-services.sh                   # ← START SERVICES
│   ├── run_minio.sh
│   └── run_rabbitmq.sh
├── systemd/
│   ├── minio.service
│   ├── rabbitmq-server.service
│   ├── opencti-platform.service
│   └── opencti-worker@.service   (redis.service do RPM cung cấp)
├── config/
│   ├── start.sh                             # Platform env vars
│   ├── redis.conf
│   ├── minio.conf
│   ├── rabbitmq.conf
│   ├── rabbitmq-env.conf
│   └── enabled_plugins
└── cert/                                    # ← tự bung từ infra package
    ├── opencti.key
    └── opencti.crt
```

---

## Step 3: Cài đặt Infrastructure

> **Chạy trên máy offline, quyền root**

### 3.1 Cài Elasticsearch (cần riêng) - Một ví dụ

Elasticsearch **không nằm trong package**. Cài theo 1 trong 2 cách:

**Cách A: Dùng tarball offline**
```bash
# Copy elasticsearch-8.x-linux-x86_64.tar.gz sang máy offline
tar -xzf elasticsearch-8.19.9-linux-x86_64.tar.gz -C /opt/
mv /opt/elasticsearch-8.19.9 /opt/elasticsearch

# Tạo user
useradd -r -s /sbin/nologin elasticsearch
chown -R elasticsearch:elasticsearch /opt/elasticsearch

# Config
cat > /opt/elasticsearch/config/elasticsearch.yml <<EOF
cluster.name: opencti-cluster
node.name: node-1
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 0.0.0.0
discovery.type: single-node
xpack.security.enabled: false
EOF

mkdir -p /var/lib/elasticsearch /var/log/elasticsearch
chown elasticsearch:elasticsearch /var/lib/elasticsearch /var/log/elasticsearch

# Tuning
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.d/90-elasticsearch.conf

# Start
su - elasticsearch -s /bin/bash -c "/opt/elasticsearch/bin/elasticsearch -d"

# Verify
curl -s http://localhost:9200
```

### 3.2 Chạy setup_infra.sh

```bash
bash /root/opencti-deploy/scripts/setup_infra.sh
```

Script sẽ tự động thực hiện 6 bước:

| Step | Hành động | Kết quả |
|------|-----------|----------|
| 1 | Cài RPMs offline (Erlang, Redis, system deps) | `redis-server`, Erlang, system libs |
| 2 | Cài MinIO binary | `/usr/local/bin/minio` |
| 3 | Extract RabbitMQ tarball | `/opt/rabbitmq/sbin/` |
| 4 | Override Redis config + copy run scripts | `/etc/redis/redis.conf`, `/opt/infra/scripts/` |
| 5 | Cài systemd services (MinIO + RabbitMQ) | `/etc/systemd/system/*.service` |
| 6 | Summary | Hiển thị kết quả + hướng dẫn |

**Thời gian:** ~30 giây (không cần compile)

> ⚠ setup_infra.sh chỉ đặt file, **không start service**. Chạy `enable-services.sh` sau.

### 3.3 Verify infrastructure

```bash
# Service status
systemctl status redis minio rabbitmq-server

# Health checks
redis-cli -a '<redis-password>' --no-auth-warning ping
# → PONG

curl -sf http://localhost:9000/minio/health/live && echo "MinIO OK"
# → MinIO OK

rabbitmqctl status | head -5
# → Status of node rabbit@localhost

curl -s http://localhost:9200
# → Elasticsearch cluster info
```

---

## Step 4: Cài đặt Application

> **Yêu cầu:** Infrastructure (Phần 3) phải chạy xong

### 4.1 Chạy setup_app.sh

```bash
bash /root/opencti-deploy/scripts/setup_app.sh
```

Script sẽ tự động thực hiện 7 bước:

| Step | Hành động | Kết quả |
|------|-----------|----------|
| 1 | Extract `opencti-app-package.tar.gz` | Temp extract |
| 2 | Cài Python 3.12 | `/opt/python312/` |
| 3 | Cài Node.js 22 | `/opt/nodejs/` |
| 4 | Deploy Platform + Worker | `/etc/saids/opencti/` |
| 5 | Tạo Python venvs + cài pip packages offline | `.python-venv/` |
| 6 | Copy SSL certs + config files | `ssl/`, `start.sh`, sysctl, logrotate |
| 7 | Cài systemd services | `opencti-platform.service`, `opencti-worker@.service` |

> ⚠ Services chưa được start — chạy `enable-services.sh` sau.

**Thời gian:** ~1-2 phút

**Flags tùy chọn:**
```bash
bash /root/opencti-deploy/scripts/setup_app.sh --skip-worker   # Chỉ platform
```

### 4.2 Verify application

```bash
# Service status
systemctl status opencti-platform opencti-worker@{1..3}

# Health check
curl -sk https://localhost:8443/health
# → {"status":"unauthorized"}  (đúng — cần auth)

# Application logs
tail -f /var/log/opencti/opencti-platform.log
tail -f /var/log/opencti-worker/opencti-worker-1.log
```

---

### 4.3 Debug node application
```bash
# 1. Tìm TẤT CẢ native addons và kiểm tra missing libs
find /etc/saids/opencti/node_modules -name "*.node" -type f -exec sh -c 'missing=$(ldd "$1" 2>&1 | grep "not found"); [ -n "$missing" ] && echo "=== $1 ===" && echo "$missing"' _ {} \;

# 2. Chạy node trực tiếp (không qua npm) để xem lỗi rõ hơn
cd /etc/saids/opencti
systemctl stop opencti-platform.service
export LD_LIBRARY_PATH="/opt/python312/lib"
export PATH="/opt/nodejs/bin:/opt/python312/bin:/etc/saids/opencti/.python-venv/bin:$PATH"
export NODE_ENV=production
export NODE_OPTIONS="--max-old-space-size=8096"
node build/back.js 2>&1 | head -50

# 3. Nếu vẫn SEGV, thử bật report
node --report-on-fatalerror --max-old-space-size=8096 build/back.js 2>&1
ls *.json  # xem report file

# 4. Hoặc dùng gdb nếu có
gdb -batch -ex run -ex bt node -- build/back.js 2>&1 | tail -30
```

---

## Phần 5: Truy cập & Sử dụng

### 5.1 Truy cập web

```
URL:      https://<IP-máy-đích>:8443
Email:    admin@v2secure.vn         (hoặc giá trị trong start.sh)
Password: **************            (giá trị trong start.sh)
```

> **Lưu ý:** Lần đầu truy cập, trình duyệt sẽ cảnh báo SSL vì dùng self-signed cert.
> Chấp nhận exception để tiếp tục.

### 5.2 Quản lý services

```bash
# Restart platform
systemctl restart opencti-platform

# Restart tất cả workers
systemctl restart opencti-worker@{1..3}

# Restart infrastructure
systemctl restart redis minio rabbitmq-server

# Xem logs real-time
journalctl -u opencti-platform -f
journalctl -u opencti-worker@1 -f
journalctl -u redis -f
```

### 5.3 Thêm/bớt workers

```bash
# Thêm worker thứ 4
systemctl enable opencti-worker@4
systemctl start opencti-worker@4

# Tắt worker thứ 3
systemctl stop opencti-worker@3
systemctl disable opencti-worker@3
```

---

## Tổng kết — Thứ tự lệnh

```bash
# ─── Máy build (có internet) ──────────────────────
cd opencti-deploy-offline
bash scripts/gen-ssl-cert.sh        # 1. Generate SSL cert
make pack-infra                     # 2. Pack infra (~15s)
make pack-app                       # 3. Pack app (~8-10 min)

# ─── Copy sang máy offline ────────────────────────
scp files/opencti-infra-package.tar.gz root@<IP>:/root/
scp files/opencti-app-package.tar.gz   root@<IP>:/root/

# ─── Máy offline (root) ──────────────────────
mkdir -p /root/opencti-deploy
tar -xzf /root/opencti-infra-package.tar.gz -C /root/opencti-deploy
cp /root/opencti-app-package.tar.gz /root/opencti-deploy/files/

# Cài Elasticsearch trước (xem Phần 3.1)

# Chạy setup infra trước khi setup application
bash /root/opencti-deploy/scripts/setup_infra.sh   # 4. Infra (~30s)
bash /root/opencti-deploy/scripts/setup_app.sh      # 5. App (~2 min)
bash /root/opencti-deploy/scripts/enable-services.sh # 6. Start all services

# Verify
systemctl status redis minio rabbitmq-server opencti-platform opencti-worker@{1..3}
curl -sk https://localhost:8443/health
```

---

## Cấu trúc thư mục sau cài đặt

```
/opt/
├── python312/          # Python 3.12 runtime
├── nodejs/             # Node.js 22 runtime
├── rabbitmq/sbin/      # RabbitMQ binaries
└── infra/scripts/      # run_*.sh (MinIO, RabbitMQ)

/usr/local/bin/minio           # MinIO binary
/usr/bin/redis-server          # Redis (from RPM)

/etc/saids/
├── opencti/            # Platform
│   ├── build/back.js   # Backend build
│   ├── public/         # Frontend build
│   ├── src/            # Source code
│   ├── ssl/            # Certificates
│   ├── start.sh        # Env vars + start
│   └── .python-venv/   # Python virtual env
└── opencti-worker/     # Worker
    ├── src/worker.py
    ├── start-worker.sh
    └── .python-venv/

/etc/
├── minio/minio.conf
├── redis/redis.conf              # RPM default, overridden by setup_infra.sh
├── rabbitmq/rabbitmq.conf
└── systemd/system/
    ├── minio.service
    ├── rabbitmq-server.service
    ├── opencti-platform.service
    └── opencti-worker@.service

/usr/lib/systemd/system/
└── redis.service                 # (do RPM cung cấp)

/var/log/
├── minio/
├── redis/                        # (do RPM tạo)
├── rabbitmq/
├── opencti/                      # Platform logs
└── opencti-worker/               # Worker logs
```

---

## Ports

| Port | Service | Protocol |
|------|---------|----------|
| 6379 | Redis | TCP |
| 9000 | MinIO API | HTTP |
| 9001 | MinIO Console | HTTP |
| 5672 | RabbitMQ AMQP | TCP |
| 15672 | RabbitMQ Management | HTTP |
| 9200 | Elasticsearch | HTTP |
| **8443** | **OpenCTI Platform** | **HTTPS** |

---

## Troubleshooting

### Platform không lên
```bash
journalctl -u opencti-platform -n 50 --no-pager
# Nguyên nhân phổ biến:
# - Elasticsearch chưa sẵn sàng → chờ ES healthy rồi restart
# - Redis password sai → kiểm tra start.sh vs redis.conf
# - SSL cert không tìm thấy → kiểm tra /etc/saids/opencti/ssl/
```

### Worker không kết nối
```bash
journalctl -u opencti-worker@1 -n 30 --no-pager
# Nguyên nhân phổ biến:
# - OPENCTI_URL sai → sửa start-worker.sh
# - OPENCTI_TOKEN không khớp → phải giống APP__ADMIN__TOKEN
# - Platform chưa sẵn sàng → chờ platform healthy rồi restart worker
```

### Redis không start
```bash
# Kiểm tra RPM đã cài chưa
rpm -qa | grep redis
# Phải có: redis-6.2.x

# Kiểm tra systemd unit
systemctl status redis
journalctl -u redis --no-pager -n 20

# Kiểm tra config
cat /etc/redis/redis.conf | grep -E 'bind|port|requirepass|dir'
```

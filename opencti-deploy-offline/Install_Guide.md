# Hướng dẫn Cài đặt OpenCTI Offline

## Tổng quan

Tài liệu này hướng dẫn cài đặt OpenCTI 6.x trên môi trường **không có internet**. Yêu cầu máy target đã cài sẵn Elasticsearch 8.x.

---

## Bước 1: Chuẩn bị trên Máy Build (có internet)

### Yêu cầu máy Build
- Rocky Linux 8 hoặc 9
- Docker + Docker Compose
- 16GB RAM
- 50GB disk trống

### Tạo packages

```bash
# Clone và vào thư mục
cd opencti-deploy-offline

# Kiểm tra files trước khi đóng gói
ls files/
# Cần có: Python-3.12.8.tgz, node-v22.15.0-linux-x64.tar.xz
#         minio, mc, rabbitmq-server-4.1.0.tar.xz

# Đóng gói infrastructure (chứa Redis RPMs, MinIO, RabbitMQ, scripts)
make pack-infra

# Build và đóng gói application (chứa Python, Node.js, OpenCTI)
make pack-app
```

### Kết quả
```
files/opencti-infra-package.tar.gz   (~200MB)
files/opencti-app-package.tar.gz    (~430MB)
```

---

## Bước 2: Copy sang Máy Target

```bash
# Từ máy Build
scp files/opencti-infra-package.tar.gz root@163.223.58.17:/root/
scp files/opencti-app-package.tar.gz root@163.223.58.17:/root/
```

---

## Bước 3: Cài đặt trên Máy Target (offline)

### Yêu cầu máy Target
- Rocky Linux 9 (minimal install)
- 8GB+ RAM
- Elasticsearch 8.x đã chạy ở port **8686**

### Giải nén

```bash
mkdir -p /root/opencti-deploy
cd /root

# Giải nén infrastructure (chứa scripts, config, systemd, rpm)
tar -xzf opencti-infra-package.tar.gz -C /root/opencti-deploy

# Copy app package vào files/
cp opencti-app-package.tar.gz /root/opencti-deploy/files/

cd /root/opencti-deploy
```

### Sửa cấu hình (nếu cần)

```bash
vi config/start.sh
```

Các biến quan trọng:
```bash
export ELASTICSEARCH__URL="http://localhost:8686"   # Địa chỉ ES
export APP__ADMIN__EMAIL="admin@example.com"       # Email admin
export APP__ADMIN__PASSWORD="Admin@2024"           # Password admin
export REDIS__PASSWORD="redis123"
export MINIO__SECRET_KEY="minio123" 
export RABBITMQ__PASSWORD="rabbitmq123"
```

### Chạy cài đặt

```bash
# 1. Cài infrastructure (Redis, MinIO, RabbitMQ)
bash scripts/setup_infra.sh

# 2. Cài application (Python, Node.js, OpenCTI)
bash scripts/setup_app.sh

# 3. Start tất cả services
bash scripts/enable-services.sh
```

---

## Bước 4: Kiểm tra

### Trạng thái services

```bash
systemctl status redis minio rabbitmq-server opencti-platform opencti-worker@{1..3}
```

### Logs

```bash
# Platform
journalctl -u opencti-platform -f

# Worker
journalctl -u opencti-worker@1 -f
```

### Truy cập

```
URL: http://163.223.58.17:8080
User: admin@example.com (hoặc email đã cấu hình)
Pass: (password đã cấu hình)
```

---

## Quản lý Services

### Stop

```bash
bash scripts/stop-app.sh     # Stop OpenCTI
bash scripts/stop-infra.sh   # Stop Redis, MinIO, RabbitMQ
```

### Restart

```bash
systemctl restart opencti-platform
systemctl restart opencti-worker@{1..3}
```

### Logs

```bash
# Tất cả logs
tail -f /var/log/opencti/*.log

# Hoặc qua journalctl
journalctl -u opencti-platform --since "10 minutes ago"
```

---

## Cấu trúc sau cài đặt

```
/opt/python312/              Python 3.12 runtime
/opt/nodejs/                 Node.js 22 runtime
/etc/saids/opencti/          Platform application
/etc/saids/opencti-worker/   Worker instances
/var/log/opencti/            Logs
/var/lib/minio/              MinIO data
/var/lib/redis/              Redis data
```

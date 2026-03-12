# Troubleshooting Guide

## Lỗi thường gặp và cách khắc phục

---

### 1. Platform không start hoặc restart liên tục

**Triệu chứng:**
```bash
systemctl status opencti-platform
# Active: activating (auto-restart)
```

**Nguyên nhân 1: Lỗi eql module SEGV**

```bash
journalctl -u opencti-platform | grep -i segv
# Segmentation fault
```

**Giải pháp:** File `check_indicator.py` đã được patch để chạy eql trong subprocess. Platform sẽ tự restart 1-2 lần rồi ổn định. Đợi 2-3 phút.

**Nguyên nhân 2: Elasticsearch không kết nối**

```bash
curl http://localhost:8686
# curl: (7) Failed to connect
```

**Giải pháp:** Kiểm tra ES đang chạy đúng port:
```bash
systemctl status elasticsearch
grep 'http.port' /etc/elasticsearch/elasticsearch.yml
# Phải là: http.port: 8686
```

---

### 2. Worker không kết nối

**Triệu chứng:**
```bash
journalctl -u opencti-worker@1 | tail -20
# Connection refused
# Token invalid
```

**Giải pháp 1:** Kiểm tra Platform đã chạy:
```bash
curl http://localhost:8080
```

**Giải pháp 2:** Token chưa được set. Token tự động được tạo sau khi Platform chạy lần đầu:
```bash
# Xem token trong config platform
grep ADMIN_TOKEN /etc/saids/opencti/start.sh

# Cập nhật token cho worker
vi /etc/saids/opencti-worker/start-worker.sh
# export OPENCTI_TOKEN="<token>"

# Restart workers
systemctl restart opencti-worker@{1..3}
```

---

### 3. Redis connection refused

**Triệu chứng:**
```bash
# Trong log platform
Error: Redis connection refused
```

**Giải pháp:**
```bash
# Kiểm tra Redis
systemctl status redis
systemctl start redis

# Kiểm tra password khớp
grep REDIS__PASSWORD /etc/saids/opencti/start.sh
grep requirepass /etc/redis/redis.conf
```

---

### 4. MinIO không start

**Triệu chứng:**
```bash
systemctl status minio
# Failed
```

**Giải pháp:**
```bash
# Tạo data directory
mkdir -p /var/lib/minio
chown minio:minio /var/lib/minio

# Restart
systemctl restart minio
```

---

### 5. RabbitMQ không start

**Triệu chứng:**
```bash
systemctl status rabbitmq-server
# erlang error
```

**Giải pháp:**
```bash
# Kiểm tra Erlang đã cài
rpm -qa | grep erlang

# Nếu thiếu, cài lại
cd /root/opencti-deploy
dnf install -y rpm/erlang*.rpm

# Restart
systemctl restart rabbitmq-server
```

---

### 6. Port bị chiếm

**Triệu chứng:**
```bash
# Address already in use
```

**Giải pháp:**
```bash
# Xem process đang dùng port
ss -tlnp | grep 8080    # Platform
ss -tlnp | grep 6379    # Redis
ss -tlnp | grep 9000    # MinIO
ss -tlnp | grep 5672    # RabbitMQ

# Kill process nếu cần
kill <pid>
```

---

### 7. Permissions / SELinux

**Triệu chứng:**
```bash
# Permission denied
# SELinux blocking
```

**Giải pháp:**
```bash
# Disable SELinux tạm thời
setenforce 0

# Hoặc check và fix permissions
chown -R opencti:opencti /etc/saids/opencti
chown -R minio:minio /var/lib/minio
chmod +x /opt/python312/bin/*
chmod +x /opt/nodejs/bin/*
```

---

## Commands Debug hữu ích

```bash
# Xem tất cả logs realtime
tail -f /var/log/opencti/*.log

# Xem status tất cả services
systemctl status redis minio rabbitmq-server opencti-platform opencti-worker@{1..3}

# Test kết nối
curl -s http://localhost:8686 | head -5    # Elasticsearch
curl -s http://localhost:8080 | head -5    # Platform
redis-cli -a <password> ping               # Redis

# Test Python runtime
/opt/python312/bin/python3.12 -c "import stix2; print('OK')"

# Check disk space
df -h

# Check memory
free -h
```

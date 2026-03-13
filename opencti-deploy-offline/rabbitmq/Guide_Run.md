# RabbitMQ Scripts Guide

## Files

| File | Vị trí | Mô tả |
|------|--------|-------|
| `rabbitmq-server-generic-unix-*.tar.xz` | Cùng với v2_setup | Tarball RabbitMQ |
| `v2_setup_rabbitmq.sh` | Cùng với tarball | First boot setup |
| `v2_start_rabbitmq.sh` | /usr/local/bin/ | Start script (systemd) |
| `v2_stop_rabbitmq.sh` | /usr/local/bin/ | Stop script (systemd) |
| `v2_uninstall_rabbitmq.sh` | Cùng với tarball | Gỡ bỏ hoàn toàn |
| `rabbitmq.service` | /etc/systemd/system/ | Systemd service |

## Usage

```bash
# 1. Setup (chọn owner)
# Với admin user (mặc định):
bash v2_setup_rabbitmq.sh

# Với user khác:
RABBITMQ_USER=master RABBITMQ_GROUP=master bash v2_setup_rabbitmq.sh

# 2. Copy scripts vào /usr/local/bin/
cp v2_start_rabbitmq.sh v2_stop_rabbitmq.sh /usr/local/bin/
chmod +x /usr/local/bin/v2_*.sh

# 3. Install service
cp rabbitmq.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now rabbitmq

# 4. Manage service
systemctl start rabbitmq
systemctl stop rabbitmq
systemctl restart rabbitmq
systemctl status rabbitmq
journalctl -u rabbitmq -f

# 5. Uninstall (xóa hết)
bash v2_uninstall_rabbitmq.sh

# Hoặc giữ data:
KEEP_DATA=true bash v2_uninstall_rabbitmq.sh
```

## Đổi Owner

Sửa `rabbitmq.service`:
```ini
User=root
Group=root
Environment="RABBITMQ_USER=root"
Environment="RABBITMQ_GROUP=root"
```

## Ports

| Port | Service |
|------|---------|
| 5672 | AMQP |
| 15672 | Management WebUI |

## Default Credentials

- User: `admin`
- Pass: `admin123`

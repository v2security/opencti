# OpenCTI Offline Deployment

Đóng gói + cài đặt OpenCTI 6.9.22 (EE) trên Rocky Linux 9 — **không cần Docker, không cần internet** trên máy đích.

## Quick Start

```bash
# 1. Đóng gói (máy có Docker + internet)
make package

# 2. Test cài đặt trong Rocky 9 container
make test
```

## Stack

| Service       | Version | Cài qua     |
|---------------|---------|-------------|
| Elasticsearch | 8.17.0  | tarball     |
| Redis         | 6.2.20  | RPM         |
| RabbitMQ      | 4.1.0   | RPM/tarball |
| MinIO         | latest  | binary      |
| Node.js       | 22      | dnf module  |
| Python        | 3.11    | RPM         |

## Makefile

| Target    | Mô tả                                       |
|-----------|---------------------------------------------|
| `test`    | Full test: clean → build → deploy → status  |
| `package` | Đóng gói offline package (~1.1GB)           |
| `status`  | Kiểm tra services trong container           |
| `logs`    | Platform logs                               |
| `exec`    | Shell vào container                         |
| `destroy` | Xóa tất cả (container + volumes)            |

## Deploy thật

```bash
# Copy lên máy đích Rocky 9
scp opencti-offline-deploy.tar.gz root@<IP>:~

# Trên máy đích
cd ~ && tar -xzf opencti-offline-deploy.tar.gz
cd opencti-deploy && bash scripts/deploy-offline.sh
```

## Gỡ cài đặt

```bash
bash scripts/uninstall-opencti.sh            # Xóa toàn bộ
bash scripts/uninstall-opencti.sh --keep-data # Giữ data
```

## Cấu trúc

```
opencti-deploy-offline/
├── Makefile                  # make test / make package
├── Dockerfile                # Rocky 9 test container
├── docker-compose.yml
├── config/                   # systemd units + start.sh
├── files/                    # ES, RabbitMQ, MinIO binaries
├── rpm/                      # Offline RPM packages (96 files)
└── scripts/
    ├── package-for-offline.sh   # Đóng gói (máy build)
    ├── deploy-offline.sh        # Cài đặt (máy đích)
    └── uninstall-opencti.sh     # Gỡ cài đặt
```

## Directory Layout trên máy đích

```
/opt/                           # CODE — binaries & application
├── python312/                  Python 3.12.8 (compiled, --enable-shared)
├── elasticsearch/              Elasticsearch 8.17.0 binaries
├── rabbitmq/                   RabbitMQ 4.1.0 binaries
├── minio/bin/                  MinIO server binary
├── opencti/                    OpenCTI Platform (Node.js)
│   ├── build/
│   ├── node_modules/
│   ├── public/
│   ├── src/
│   └── .python-venv/
└── opencti-worker/             OpenCTI Worker (Python)
    ├── worker.py
    ├── venv/
    └── wheels/

/etc/                           # CONFIG — configuration files
├── opencti/
│   ├── start.sh                Platform startup script
│   └── ssl/
│       ├── opencti.key
│       └── opencti.crt
├── opencti-worker/
│   ├── config.yml              Worker config
│   └── worker.env              Worker environment vars
├── elasticsearch/
│   ├── elasticsearch.yml
│   └── jvm.options.d/
├── rabbitmq/
│   └── rabbitmq.conf
├── default/minio               MinIO env config
└── redis/redis.conf

/var/lib/                       # DATA — persistent data
├── elasticsearch/              Elasticsearch indices
├── minio/data/                 MinIO object storage
├── rabbitmq/mnesia/            RabbitMQ data
└── redis/                      Redis data

/var/log/v2-ti/                 # LOGS — all application logs
├── opencti/                    Platform stdout/stderr
├── opencti-worker/             Worker stdout/stderr
├── elasticsearch/              Elasticsearch logs
└── rabbitmq/                   RabbitMQ logs
```

## Yêu cầu

- **Máy build**: Docker, Git, ~5GB disk
- **Máy đích**: Rocky Linux 9, 16GB+ RAM, 100GB+ disk
- **Test container**: Docker với cgroup v2, privileged

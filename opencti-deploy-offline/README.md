# OpenCTI Offline Deployment

Deploy OpenCTI trên Rocky Linux 9 **không cần internet** trên máy target.

## Tổng quan: 2 Phần

```sh
MÁY BUILD:  bash scripts/pack_app.sh
  01 → Build Python 3.12 (Docker)
  02 → Download Node.js 22 (binary)
  03 → Build backend (yarn build:prod)
  04 → Build frontend (yarn build:standalone)
  05 → Copy source + build artifacts → tar.gz
  06 → Download Python packages → tar.gz
  07 → Assemble ALL → opencti-app-package.tar.gz

MÁY TARGET: 
  bash scripts/setup_infra.sh   → Redis + MinIO + RabbitMQ
  bash scripts/setup_app.sh     → Extract + install + start systemd
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    MÁY BUILD (có internet)                      │
│                                                                 │
│  Part 1: Infra        │  Part 2: App                            │
│  (đã có sẵn)          │  bash scripts/pack_app.sh                   │
│  • minio binary       │    01 → Build Python 3.12 (Docker)      │
│  • redis tarball      │    02 → Download Node.js 22 (binary)    │
│  • rabbitmq tarball   │    03 → Build backend (yarn build:prod) │
│  • erlang RPMs        │    04 → Build frontend (React + Relay)  │
│  • system RPMs        │    05 → Copy source + build artifacts   │
│                       │    06 → Download Python packages        │
│                       │    07 → Pack ALL → 1 file .tar.gz       │
│                       │                                         │
│  Copy toàn bộ thư mục opencti-deploy-offline/ → máy target      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   MÁY TARGET (offline)                          │
│                                                                 │
│  bash scripts/setup_infra.sh     ← Part 1: Redis+MinIO+RabbitMQ │
│  bash scripts/setup_app.sh       ← Part 2: Python+Node+OpenCTI  │
│                                                                 │
│  Done! → https://localhost:8443                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Part 1: Infrastructure (Infra)

Cài đặt **Redis + MinIO + RabbitMQ** từ binary/source đã chuẩn bị sẵn.

**Files cần có:**
```
files/
├── minio                                  ← MinIO binary
├── mc                                     ← MinIO client (optional)
├── redis-8.4.2.tar.gz                     ← Redis source (compile on target)
└── rabbitmq-server-generic-unix-4.2.0.tar.xz ← RabbitMQ

rpm/
├── erlang-*.rpm                           ← Erlang (for RabbitMQ)
└── *.rpm                                  ← System dependencies (gcc, etc.)

config/
├── redis.conf
├── minio.conf
├── rabbitmq.conf
├── rabbitmq-env.conf
└── enabled_plugins
```

**Chạy trên máy target:**
```bash
bash scripts/setup_infra.sh
```

## Part 2: Application (App)

Cài đặt **Python 3.12 + Node.js 22 + OpenCTI Platform + Worker**.

### Bước 1: Đóng gói (trên máy build)

```bash
bash scripts/pack_app.sh

# Options:
#   --skip-runtimes   Reuse existing python312.tar.gz + nodejs22.tar.gz
#   --skip-deps       Skip Python package download

# Or run individual steps:
bash scripts/01-build-python.sh     # → files/python312.tar.gz  (compile in Docker)
bash scripts/02-build-nodejs.sh     # → files/nodejs22.tar.gz   (pre-built binary)
bash scripts/03-build-backend.sh    # → opencti-graphql/build/  (yarn build:prod)
bash scripts/04-build-frontend.sh   # → opencti-front/builder/prod/build/ (React + Relay)
bash scripts/05-copy-source.sh      # → files/opencti-source.tar.gz
bash scripts/06-download-deps.sh    # → files/python-deps.tar.gz
```

Script `pack_app.sh` runs 6 sub-scripts then assembles:
1. ✅ Build Python 3.12 runtime (Docker, `--enable-shared`)
2. ✅ Download Node.js 22 pre-built binary (từ nodejs.org)
3. ✅ Build OpenCTI backend (yarn install + build:prod)
4. ✅ Build OpenCTI frontend (yarn build:standalone → public/)
5. ✅ Copy OpenCTI source + build artifacts
6. ✅ Download Python packages (offline pip)
7. ✅ Pack ALL → `files/opencti-app-package.tar.gz`

### Bước 2: Deploy (trên máy target)

```bash
bash scripts/setup_app.sh

# Options:
#   --skip-worker   Chỉ deploy platform
#   --skip-start    Deploy nhưng không start services
```

Script `setup_app.sh` sẽ tự động:
1. ✅ Extract package
2. ✅ Install Python 3.12 → `/opt/python312`
3. ✅ Install Node.js 22 → `/opt/nodejs`
4. ✅ Deploy OpenCTI Platform → `/etc/saids/application/opencti`
5. ✅ Deploy Worker → `/etc/saids/application/opencti-worker`
6. ✅ Setup Python venvs + install packages (offline)
7. ✅ Copy SSL certs + config files
8. ✅ Install + start systemd services

## Quick Start (full workflow)

```bash
# ═══ Trên máy BUILD (có internet) ═══

# 1. Chuẩn bị Part 1 files (minio, redis, rabbitmq, RPMs) — đã có sẵn
# 2. Đóng gói Part 2:
bash scripts/pack_app.sh

# 3. Copy toàn bộ thư mục sang máy target:
rsync -avz opencti-deploy-offline/ root@target:/root/opencti-deploy/
# Hoặc: tar czf deploy.tar.gz opencti-deploy-offline/ && scp ... 

# ═══ Trên máy TARGET (offline) ═══

cd /root/opencti-deploy

# 4. Part 1: Cài infra
bash scripts/setup_infra.sh

# 5. Part 2: Cài app
bash scripts/setup_app.sh
```

## Cấu trúc thư mục

```
opencti-deploy-offline/
├── scripts/
│   ├── pack_app.sh                  ★ Pack all → files/opencti-app-package.tar.gz
│   ├── 01-build-python.sh       ← Build Python 3.12 in Docker
│   ├── 02-build-nodejs.sh       ← Download Node.js 22 pre-built binary
│   ├── 03-build-backend.sh      ← Build backend (yarn install + build:prod)
│   ├── 04-build-frontend.sh     ← Build frontend (React + Relay → public/)
│   ├── 05-copy-source.sh        ← Copy OpenCTI source + build artifacts
│   ├── 06-download-deps.sh      ← Download Python packages
│   ├── setup_infra.sh           ★ Deploy Part 1 (trên máy target)
│   ├── setup_app.sh             ★ Deploy Part 2 (trên máy target)
│   ├── gen-ssl-cert.sh          ← Tạo SSL self-signed cert
│   ├── run_minio.sh             ← Systemd run script
│   ├── run_redis.sh             ← Systemd run script
│   └── run_rabbitmq.sh          ← Systemd run script
├── config/
│   ├── start.sh                 ← Platform env vars (⚠ chứa secrets)
│   ├── start-worker.sh          ← Worker env vars (⚠ chứa secrets)
│   ├── redis.conf
│   ├── minio.conf
│   ├── rabbitmq.conf
│   ├── rabbitmq-env.conf
│   └── enabled_plugins
├── systemd/
│   ├── minio.service
│   ├── redis.service
│   ├── rabbitmq-server.service
│   ├── opencti-platform.service
│   └── opencti-worker@.service
├── cert/
│   ├── opencti.key              ← SSL private key (⚠ KHÔNG commit)
│   └── opencti.crt              ← SSL certificate
├── files/
│   ├── opencti-app-package.tar.gz  ★ Output Part 2 (tất cả trong 1 file)
│   ├── minio                       ← MinIO binary
│   ├── mc                          ← MinIO client
│   ├── redis-8.4.2.tar.gz          ← Redis source
│   ├── rabbitmq-server-*.tar.xz    ← RabbitMQ
│   ├── Python-3.12.8.tgz           ← Python source (dùng khi build)
│   ├── python312.tar.gz            ← Python runtime (01-build-python.sh)
│   ├── nodejs22.tar.gz             ← Node.js pre-built binary (02-build-nodejs.sh)
│   ├── opencti-source.tar.gz       ← OpenCTI source (05-copy-source.sh)
│   └── python-deps.tar.gz          ← Python packages (06-download-deps.sh)
├── rpm/
│   ├── erlang-*.rpm
│   └── *.rpm                       ← System dependencies
├── Dockerfile                       ← Test container
├── docker-compose.yml               ← Test stack
└── Makefile                         ← Test automation
```

## Kết quả sau khi deploy trên target

```
/opt/python312/                        ← Python 3.12 runtime (compiled, --enable-shared)
/opt/nodejs/                           ← Node.js 22 runtime (pre-built binary)
/opt/minio/bin/minio                   ← MinIO binary
/opt/redis/bin/redis-server            ← Redis (compiled)
/opt/rabbitmq/sbin/                    ← RabbitMQ binaries

/etc/saids/application/opencti/        ← OpenCTI Platform
/etc/saids/application/opencti-worker/ ← OpenCTI Workers

/etc/systemd/system/
├── redis.service
├── minio.service
├── rabbitmq-server.service
├── opencti-platform.service
└── opencti-worker@.service            → @1, @2, @3

Ports:
  6379   Redis
  9000   MinIO API
  9001   MinIO Console
  5672   RabbitMQ AMQP
  15672  RabbitMQ Management
  8443   OpenCTI Platform (HTTPS)
```

## Makefile commands

```bash
make pack              # Pack ALL → files/opencti-app-package.tar.gz
make build-python      # Build Python 3.12 runtime (Docker)
make build-nodejs      # Download Node.js 22 pre-built binary
make copy-source       # Copy OpenCTI source code
make download-deps     # Download Python packages

make test              # Test Part 1 (infra) trong Docker
make test-all          # Test full stack (infra + app) trong Docker
make deploy            # Chạy setup_infra.sh trong test container
make deploy-app        # Chạy setup_app.sh trong test container
make status            # Kiểm tra tất cả services
make logs              # Xem logs
make exec              # Shell vào test container
make destroy           # Xóa tất cả test resources
```

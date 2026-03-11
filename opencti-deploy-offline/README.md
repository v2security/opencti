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
│  (đã có sẵn)          │  bash scripts/pack_app.sh               │
│  • minio binary       │    01 → Build Python 3.12 (Docker)      │
│  • redis RPM          │    02 → Download Node.js 22 (binary)    │
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

Cài đặt **Redis (RPM) + MinIO (binary) + RabbitMQ (tarball)** đã chuẩn bị sẵn.

**Files cần có:**
```
files/
├── minio                                  ← MinIO binary
├── mc                                     ← MinIO client (optional)
└── rabbitmq-server-generic-unix-4.2.0.tar.xz ← RabbitMQ

rpm/
├── erlang-*.rpm                           ← Erlang (for RabbitMQ)
├── redis-*.rpm                            ← Redis (RPM, cài qua dnf)
└── *.rpm                                  ← System dependencies

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
#   --skip-worker   Chỉ deploy platform (không deploy worker)
```

Script `setup_app.sh` sẽ tự động:
1. ✅ Extract package
2. ✅ Install Python 3.12 → `/opt/python312`
3. ✅ Install Node.js 22 → `/opt/nodejs`
4. ✅ Deploy OpenCTI Platform → `/etc/saids/opencti`
5. ✅ Deploy Worker → `/etc/saids/opencti-worker`
6. ✅ Setup Python venvs + install packages (offline)
7. ✅ Copy SSL certs + config files

> ⚠ Services chưa được start — chạy `bash scripts/enable-services.sh` sau khi setup xong.

## Quick Start (full workflow)

```bash
# ═══ Trên máy BUILD (có internet) ═══

# 1. Chuẩn bị Part 1 files (minio, redis RPM, rabbitmq, RPMs) — đã có sẵn
# 2. Đóng gói Part 2:
bash scripts/pack_app.sh

# 3. Copy toàn bộ thư mục sang máy target:
rsync -avz opencti-deploy-offline/ root@target:/root/opencti-deploy/
# Hoặc: tar czf deploy.tar.gz opencti-deploy-offline/ && scp ... 

# ═══ Trên máy TARGET (offline) ═══

cd /root/opencti-deploy

# 4. Part 1: Cài infra (file placement only)
bash scripts/setup_infra.sh

# 5. Part 2: Cài app (file placement only)
bash scripts/setup_app.sh

# 6. Start all services
bash scripts/enable-services.sh
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
│   ├── run_minio.sh             ← Systemd run script (MinIO)
│   ├── run_rabbitmq.sh          ← Systemd run script (RabbitMQ)
│   └── enable-services.sh       ← Start all services + health checks
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
│   ├── rabbitmq-server.service
│   ├── opencti-platform.service
│   └── opencti-worker@.service  (redis.service do RPM cung cấp)
├── cert/
│   ├── opencti.key              ← SSL private key (⚠ KHÔNG commit)
│   └── opencti.crt              ← SSL certificate
├── files/
│   ├── opencti-app-package.tar.gz  ★ Output Part 2 (tất cả trong 1 file)
│   ├── minio                       ← MinIO binary
│   ├── mc                          ← MinIO client
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
/usr/local/bin/minio                   ← MinIO binary
/usr/bin/redis-server                  ← Redis (from RPM)
/opt/rabbitmq/sbin/                    ← RabbitMQ binaries

/etc/saids/opencti/        ← OpenCTI Platform
/etc/saids/opencti-worker/ ← OpenCTI Workers

/etc/systemd/system/
├── minio.service
├── rabbitmq-server.service
├── opencti-platform.service
└── opencti-worker@.service            → @1, @2, @3

/usr/lib/systemd/system/
└── redis.service                      ← (do RPM cung cấp)

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
#   make pack            # Pack OpenCTI source + deps
#   make test            # Full: pack + build + deploy infra + app + status
#   make test-infra      # Infra only: build + deploy infra + status
#   make status          # Service status
#   make exec            # Shell vào container
#   make destroy         # Xóa tất cả containers
#   make destroy-pack    # Xóa build artifacts
```

## RPM Dependencies
```bash
[master@rocky8 rpm]$ tree .

├── acl-2.3.1-4.el9.x86_64.rpm
├── alternatives-1.24-2.el9.x86_64.rpm
├── audit-libs-3.1.5-7.el9.x86_64.rpm
├── basesystem-11-13.el9.0.1.noarch.rpm
├── bash-5.1.8-9.el9.x86_64.rpm
├── binutils-2.35.2-67.el9_7.1.x86_64.rpm
├── bzip2-libs-1.0.8-10.el9_5.x86_64.rpm
├── ca-certificates-2025.2.80_v9.0.305-91.el9.noarch.rpm
├── coreutils-8.32-39.el9.x86_64.rpm
├── coreutils-common-8.32-39.el9.x86_64.rpm
├── cpp-11.5.0-11.el9.x86_64.rpm
├── cracklib-2.9.6-27.el9.x86_64.rpm
├── cracklib-dicts-2.9.6-27.el9.x86_64.rpm
├── crypto-policies-20250905-1.git377cc42.el9.noarch.rpm
├── curl-7.76.1-35.el9_7.3.x86_64.rpm
├── dbus-1.12.20-8.el9.x86_64.rpm
├── dbus-broker-28-7.el9.x86_64.rpm
├── dbus-common-1.12.20-8.el9.noarch.rpm
├── erlang-27.2.4-1.el9.x86_64.rpm
├── expat-2.5.0-5.el9_7.1.x86_64.rpm
├── filesystem-3.16-5.el9.x86_64.rpm
├── findutils-4.8.0-7.el9.x86_64.rpm
├── gawk-5.1.0-6.el9.x86_64.rpm
├── gawk-all-langpacks-5.1.0-6.el9.x86_64.rpm
├── gcc-11.5.0-11.el9.x86_64.rpm
├── gcc-c++-11.5.0-11.el9.x86_64.rpm
├── glibc-2.34-231.el9_7.10.x86_64.rpm
├── glibc-common-2.34-231.el9_7.10.x86_64.rpm
├── glibc-devel-2.34-231.el9_7.10.x86_64.rpm
├── glibc-gconv-extra-2.34-231.el9_7.10.x86_64.rpm
├── glibc-headers-2.34-231.el9_7.10.x86_64.rpm
├── glibc-langpack-en-2.34-231.el9_7.10.x86_64.rpm
├── glibc-minimal-langpack-2.34-231.el9_7.10.x86_64.rpm
├── gmp-6.2.0-13.el9.x86_64.rpm
├── grep-3.6-5.el9.x86_64.rpm
├── gzip-1.12-1.el9.x86_64.rpm
├── hostname-3.23-6.el9.x86_64.rpm
├── iproute-6.14.0-2.el9.x86_64.rpm
├── isl-0.16.1-15.el9.x86_64.rpm
├── kernel-headers-5.14.0-611.36.1.el9_7.x86_64.rpm
├── kmod-libs-28-11.el9.x86_64.rpm
├── libacl-2.3.1-4.el9.x86_64.rpm
├── libattr-2.5.1-3.el9.x86_64.rpm
├── libblkid-2.37.4-21.el9.x86_64.rpm
├── libcap-2.48-10.el9.x86_64.rpm
├── libcap-ng-0.8.2-7.el9.x86_64.rpm
├── libdb-5.3.28-57.el9_6.x86_64.rpm
├── libeconf-0.4.1-4.el9.x86_64.rpm
├── libfdisk-2.37.4-21.el9.x86_64.rpm
├── libffi-3.4.2-8.el9.x86_64.rpm
├── libgcc-11.5.0-11.el9.x86_64.rpm
├── libgcrypt-1.10.0-11.el9.x86_64.rpm
├── libgpg-error-1.42-5.el9.x86_64.rpm
├── libmount-2.37.4-21.el9.x86_64.rpm
├── libmpc-1.2.1-4.el9.x86_64.rpm
├── libnsl2-2.0.0-1.el9.0.1.x86_64.rpm
├── libpwquality-1.4.4-8.el9.x86_64.rpm
├── libseccomp-2.5.2-2.el9.x86_64.rpm
├── libselinux-3.6-3.el9.x86_64.rpm
├── libsemanage-3.6-5.el9_6.x86_64.rpm
├── libsepol-3.6-3.el9.x86_64.rpm
├── libsigsegv-2.13-4.el9.x86_64.rpm
├── libsmartcols-2.37.4-21.el9.x86_64.rpm
├── libstdc++-devel-11.5.0-11.el9.x86_64.rpm
├── libtasn1-4.16.0-9.el9.x86_64.rpm
├── libtirpc-1.3.3-9.el9.x86_64.rpm
├── libutempter-1.2.1-6.el9.x86_64.rpm
├── libuuid-2.37.4-21.el9.x86_64.rpm
├── libxcrypt-4.4.18-3.el9.x86_64.rpm
├── libxcrypt-compat-4.4.18-3.el9.x86_64.rpm
├── libxcrypt-devel-4.4.18-3.el9.x86_64.rpm
├── libzstd-1.5.5-1.el9.x86_64.rpm
├── lz4-libs-1.9.3-5.el9.x86_64.rpm
├── make-4.3-8.el9.x86_64.rpm
├── mpfr-4.1.0-7.el9.x86_64.rpm
├── ncurses-base-6.2-12.20210508.el9.noarch.rpm
├── ncurses-libs-6.2-12.20210508.el9.x86_64.rpm
├── openssl-3.5.1-7.el9_7.x86_64.rpm
├── openssl-fips-provider-3.5.1-7.el9_7.x86_64.rpm
├── openssl-libs-3.5.1-7.el9_7.x86_64.rpm
├── p11-kit-0.25.3-3.el9_5.x86_64.rpm
├── p11-kit-trust-0.25.3-3.el9_5.x86_64.rpm
├── pam-1.5.1-26.el9_6.x86_64.rpm
├── pcre2-10.40-6.el9.x86_64.rpm
├── pcre2-syntax-10.40-6.el9.noarch.rpm
├── pcre-8.44-4.el9.x86_64.rpm
├── popt-1.18-8.el9.x86_64.rpm
├── procps-ng-3.3.17-14.el9.x86_64.rpm
├── readline-8.1-4.el9.x86_64.rpm
├── rocky-gpg-keys-9.7-1.4.el9.noarch.rpm
├── rocky-release-9.7-1.4.el9.noarch.rpm
├── rocky-repos-9.7-1.4.el9.noarch.rpm
├── sed-4.8-9.el9.x86_64.rpm
├── setup-2.13.7-10.el9.noarch.rpm
├── shadow-utils-4.9-15.el9.x86_64.rpm
├── systemd-252-55.el9_7.7.rocky.0.1.x86_64.rpm
├── systemd-libs-252-55.el9_7.7.rocky.0.1.x86_64.rpm
├── systemd-pam-252-55.el9_7.7.rocky.0.1.x86_64.rpm
├── systemd-rpm-macros-252-55.el9_7.7.rocky.0.1.noarch.rpm
├── tar-1.34-9.el9_7.x86_64.rpm
├── tzdata-2025c-1.el9.noarch.rpm
├── util-linux-2.37.4-21.el9.x86_64.rpm
├── util-linux-core-2.37.4-21.el9.x86_64.rpm
├── which-2.21-30.el9_6.x86_64.rpm
├── xz-libs-5.2.5-8.el9_0.x86_64.rpm
└── zlib-1.2.11-40.el9.x86_64.rpm

0 directories, 106 files
```
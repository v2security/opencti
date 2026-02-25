# OpenCTI - Hướng dẫn Vận hành & Nâng cấp

> **TL;DR** — Nâng cấp lên version mới chỉ 1 lệnh:
> ```bash
> make upgrade VERSION=6.10.0
> ```

---

## Mục lục

1. [Cấu trúc dự án](#1-cấu-trúc-dự-án)
2. [Quick Reference — Makefile Commands](#2-quick-reference--makefile-commands)
3. [Nâng cấp Version (Step-by-step)](#3-nâng-cấp-version-step-by-step)
4. [Cài đặt lần đầu (Fresh Install)](#4-cài-đặt-lần-đầu-fresh-install)
5. [Cách EE Bypass hoạt động](#5-cách-ee-bypass-hoạt-động)
6. [Cấu hình AI](#6-cấu-hình-ai)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Cấu trúc dự án

```
/opencti/
├── .env                    # ← Biến môi trường (OPENCTI_VERSION, AI config, credentials)
├── docker-compose.yml      # ← Docker Compose (dùng ${OPENCTI_VERSION} từ .env)
├── Makefile                # ← Tất cả commands: make upgrade, make restart, make logs...
├── patch_ee.sh             # ← Script patch EE + build Docker image
├── Dockerfile.patch        # ← Auto-generated bởi patch_ee.sh
├── rabbitmq.conf           # ← Cấu hình RabbitMQ
├── .docs/
│   └── setup-guide.md      # ← Tài liệu này
└── opencti-source/         # ← Source code OpenCTI (auto clone/checkout by patch_ee.sh)
    └── opencti-platform/opencti-graphql/src/
        ├── enterprise-edition/ee.ts      # Patched: bypass EE check
        └── modules/settings/licensing.ts # Patched: bypass license check
```

### Biến quan trọng trong `.env`

| Biến | Mô tả | Ví dụ |
|------|--------|-------|
| `OPENCTI_VERSION` | Version OpenCTI hiện tại | `6.9.22` |
| `AI_TYPE` | AI provider | `openai` |
| `AI_TOKEN` | API key cho AI | `sk-...` |
| `AI_MODEL` | Model AI | `gpt-4` |

> **Tất cả images** trong `docker-compose.yml` đều dùng `${OPENCTI_VERSION}` — **không hardcode** version ở bất kỳ đâu.

---

## 2. Quick Reference — Makefile Commands

```bash
# Xem tất cả commands
make help

# ═══════════════════════════════════════
# UPGRADE
# ═══════════════════════════════════════
make upgrade VERSION=6.10.0    # Patch + build + restart (1 lệnh duy nhất)
make patch VERSION=6.10.0      # Chỉ patch + build (không restart)

# ═══════════════════════════════════════
# VẬN HÀNH HÀNG NGÀY
# ═══════════════════════════════════════
make start                     # Start containers
make stop                      # Stop containers
make restart                   # Restart toàn bộ
make restart-opencti           # Restart chỉ OpenCTI platform

# ═══════════════════════════════════════
# MONITORING
# ═══════════════════════════════════════
make status                    # Trạng thái + images
make ps                        # Docker ps format đẹp
make logs                      # Logs OpenCTI (follow)
make logs-worker               # Logs workers
make logs-all                  # Logs tất cả
make health                    # Check health endpoint

# ═══════════════════════════════════════
# INFO & CLEANUP
# ═══════════════════════════════════════
make version                   # Version hiện tại
make info                      # Thông tin chi tiết
make clean                     # Xóa dangling images
make clean-all                 # Xóa tất cả images patched cũ
```

---

## 3. Nâng cấp Version (Step-by-step)

### Cách 1: Tự động (khuyến nghị)

```bash
# Một lệnh duy nhất — patch, build, restart tất cả:
make upgrade VERSION=6.10.0
```

**Xong.** Đợi ~5-15 phút (build lần đầu), sau đó kiểm tra:

```bash
make status    # Tất cả containers healthy?
make logs      # Có lỗi gì không?
```

### Cách 2: Từng bước (nếu muốn kiểm soát)

```bash
# Step 1: Patch source + build Docker image
#   - Checkout source tại tag mới
#   - Patch ee.ts + licensing.ts
#   - Build multi-stage Docker image
#   - Tự động update OPENCTI_VERSION trong .env
./patch_ee.sh 6.10.0

# Step 2: Kiểm tra build thành công
make version
# Output: OPENCTI_VERSION=6.10.0

# Step 3: Restart containers (pull worker/connector images mới)
make restart

# Step 4: Kiểm tra
make status
make logs
```

### Flow nội bộ khi chạy `make upgrade`

```
┌─────────────────────────────────────────────────────────┐
│  make upgrade VERSION=6.10.0                            │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │  patch_ee.sh 6.10.0                              │   │
│  │                                                  │   │
│  │  [1/6] git checkout tag 6.10.0                   │   │
│  │  [2/6] Verify ee.ts + licensing.ts exist         │   │
│  │  [3/6] Patch 8 points in source TypeScript       │   │
│  │  [4/6] Generate Dockerfile.patch                 │   │
│  │  [5/6] docker build multi-stage                  │   │
│  │        Stage 1: node:22-alpine → yarn build:prod │   │
│  │        Stage 2: Copy back.js → official image    │   │
│  │  [6/6] Update .env OPENCTI_VERSION=6.10.0        │   │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
│  docker compose down                                    │
│  docker compose up -d                                   │
│    → Pull opencti/worker:6.10.0                         │
│    → Pull opencti/connector-*:6.10.0                    │
│    → Start opencti/platform:6.10.0-patched              │
│                                                         │
│  ✅ Done!                                               │
└─────────────────────────────────────────────────────────┘
```

### Tại sao không cần sửa `docker-compose.yml` khi upgrade?

Vì tất cả images dùng biến `${OPENCTI_VERSION}` từ `.env`:

```yaml
# docker-compose.yml
opencti:
  image: opencti/platform:${OPENCTI_VERSION}-patched
worker:
  image: opencti/worker:${OPENCTI_VERSION}
connector-export-file-stix:
  image: opencti/connector-export-file-stix:${OPENCTI_VERSION}
# ... tất cả connectors tương tự
```

Khi `patch_ee.sh` update `OPENCTI_VERSION=6.10.0` trong `.env`, tất cả images tự động cập nhật version.

---

## 4. Cài đặt lần đầu (Fresh Install)

```bash
# 1. Clone repo hoặc copy files vào /opencti/
cd /opencti

# 2. Copy .env.sample thành .env và sửa credentials
cp .env.sample .env
vi .env    # Sửa passwords, tokens, AI key

# 3. Patch + build + start
make upgrade VERSION=6.9.22

# 4. Truy cập
#    URL: http://<server-ip>:8080
#    Login: xem OPENCTI_ADMIN_EMAIL / OPENCTI_ADMIN_PASSWORD trong .env
```

---

## 5. Cách EE Bypass hoạt động

### EE License Check Flow (gốc)

```
Frontend → GraphQL query → settings.js
  → valid_enterprise_edition = eeInfo.license_validated
    → ee.ts:
        isEnterpriseEdition(context)        → check settings
        isEnterpriseEditionFromSettings()   → check valid_enterprise_edition
        checkEnterpriseEdition(context)     → throw if not EE
    → licensing.ts:
        decodeLicensePem()                  → validate license PEM
          fallback → { license_validated: false, ... }
```

### 8 patches bypass

**File `ee.ts`** — thay toàn bộ body 3 functions:

| # | Function | Gốc | Patched |
|---|----------|-----|---------|
| 1 | `isEnterpriseEdition` | Check settings from cache | `return true;` |
| 2 | `isEnterpriseEditionFromSettings` | Check `valid_enterprise_edition` | `return true;` |
| 3 | `checkEnterpriseEdition` | Throw `UnsupportedError` if not EE | `return;` |

**File `licensing.ts`** — sửa fallback return block:

| # | Field | Gốc | Patched |
|---|-------|-----|---------|
| 4 | `license_validated` | `false` | `true` |
| 5 | `license_valid_cert` | `false` | `true` |
| 6 | `license_expired` | `true` | `false` |
| 7 | `license_type` | `'trial'` | `'standard'` |
| 8 | `license_global` | `false` | `true` |

### Multi-stage Docker Build

```
┌─ Stage 1: backend-builder ────────────────────────┐
│  FROM node:22-alpine                              │
│  Copy patched source TypeScript                   │
│  yarn install → yarn build:prod                   │
│  Output: /opt/opencti-build/.../build/back.js     │
└───────────────────────────────────────────────────┘
                    │
                    ▼
┌─ Stage 2: final image ────────────────────────────┐
│  FROM opencti/platform:<VERSION>  (official)      │
│  COPY back.js from Stage 1                        │
│  → Frontend giữ nguyên, chỉ thay backend         │
│  Tag: opencti/platform:<VERSION>-patched          │
└───────────────────────────────────────────────────┘
```

---

## 6. Cấu hình AI

### Biến trong `.env`

```env
AI_TYPE=openai                          # openai | mistralai | azureopenai
AI_ENDPOINT=                            # Custom endpoint (để trống = mặc định)
AI_TOKEN=sk-your-openai-api-key-here    # ⚠️ THAY BẰNG API KEY THẬT
AI_MODEL=gpt-4                          # Model cho text generation
AI_MODEL_IMAGES=dall-e-3                # Model cho image generation
AI_MAX_TOKENS=30000                     # Max tokens per request
AI_TIMEOUT=60000                        # Timeout (ms)
```

### AI Features (yêu cầu EE — đã bypass)

| Chức năng | Mô tả |
|-----------|--------|
| **AI Summary** | Tóm tắt entity (Reports, Incidents, Malware...) |
| **AI Insights** | Phân tích threat intelligence |
| **AI Chat / Ask AI** | Hỏi đáp về dữ liệu CTI |
| **AI-assisted content** | Tạo nội dung tự động |
| **AI-powered search** | Tìm kiếm bằng ngôn ngữ tự nhiên |
| **AI Image generation** | Tạo hình ảnh minh họa |

> ⚠️ **Quan trọng**: Phải thay `AI_TOKEN` bằng API key thật để dùng AI.

---

## 7. Troubleshooting

### ❌ Version mismatch

```
Error: Your platform data are too recent to start on version X.X.X
```

**Nguyên nhân**: Data trong Elasticsearch đã migrate lên version cao hơn image.

**Fix**: Upgrade lên đúng version data yêu cầu:
```bash
make upgrade VERSION=<version-trong-error-message>
```

### ❌ Build failed — TypeScript error

**Nguyên nhân**: OpenCTI thay đổi cấu trúc `ee.ts` hoặc `licensing.ts` ở version mới.

**Fix**: Đọc file gốc, điều chỉnh patches trong `patch_ee.sh`:
```bash
# Xem file gốc
cd opencti-source
git checkout <VERSION>
cat opencti-platform/opencti-graphql/src/enterprise-edition/ee.ts
cat opencti-platform/opencti-graphql/src/modules/settings/licensing.ts
```

### ❌ Container unhealthy

```bash
# Xem logs chi tiết
make logs

# Restart
make restart

# Nếu vẫn lỗi — rebuild
make build
make restart
```

### ❌ AI không hoạt động

1. Kiểm tra `AI_TOKEN` trong `.env` (phải là key thật, không phải placeholder)
2. Kiểm tra `AI__ENABLED=true` trong `docker-compose.yml`
3. Restart: `make restart-opencti`

---

## Kiến trúc hệ thống

```
┌──────────────────────────────────────────────────────────┐
│                     Docker Compose                        │
├──────────────┬────────────┬────────────┬─────────────────┤
│  OpenCTI     │  Redis     │  Elastic   │  MinIO          │
│  Platform    │  8.4.0     │  Search    │  (S3 Storage)   │
│  (patched)   │            │  8.19.x    │                 │
├──────────────┼────────────┴────────────┴─────────────────┤
│  RabbitMQ    │  Workers (x3)                              │
│  4.2-mgmt    │                                            │
├──────────────┼────────────────────────────────────────────┤
│  Connectors  │  export-stix, export-csv, export-txt,      │
│              │  import-stix, import-document, import-yara, │
│              │  import-external-ref, analysis,             │
│              │  opencti-datasets, mitre                    │
├──────────────┼────────────────────────────────────────────┤
│  Other       │  xtm-composer, rsa-key-generator           │
└──────────────┴────────────────────────────────────────────┘
```

---

*Cập nhật: 25/02/2026*

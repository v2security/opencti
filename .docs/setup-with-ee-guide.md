# OpenCTI Fork — Logic tổng quan

## 1. Kiến trúc repo

OpenCTI là **monorepo**, frontend + backend chung 1 repo:

```
opencti-platform/
├── opencti-graphql/    ← Backend (Node.js, TypeScript, GraphQL)
├── opencti-front/      ← Frontend (React, Relay)
└── opencti-dev/        ← Docker Compose cho dev (ES, Redis, RabbitMQ, MinIO)
```

**Nhưng KHÔNG build chung tất cả.** Image Docker gốc của OpenCTI (`opencti/platform:6.9.22`) đã build sẵn cả frontend + backend. Repo này chỉ **build lại backend** (file `back.js`), rồi **overlay đè lên** image gốc. Frontend giữ nguyên.

---

## 2. Luồng build — Dockerfile.patch

```
┌─────────────────────────────────────────────────────────┐
│ docker compose build opencti                            │
│ (hoặc: make patch)                                      │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────── Stage 1: Build ──────────────────────────┐
│ FROM node:22-alpine                                     │
│                                                         │
│ 1. COPY source từ opencti-platform/opencti-graphql/     │
│    (lấy trực tiếp từ code trong repo, KHÔNG clone thêm) │
│                                                         │
│ 2. yarn install (cài dependencies)                      │
│                                                         │
│ 3. RUN: Patch EE trực tiếp trong container              │
│    - Ghi đè ee.ts → luôn return true                    │
│    - sed licensing.ts → license luôn validated          │
│    (Source trong git KHÔNG bị sửa, chỉ sửa trong Docker)│
│                                                         │
│ 4. yarn build:prod → ra file build/back.js              │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────── Stage 2: Overlay ────────────────────────┐
│ FROM opencti/platform:6.9.22  (image gốc, có frontend)  │
│                                                         │
│ COPY back.js đè lên → backend mới, frontend giữ nguyên  │
│                                                         │
│ → Image ra: opencti/platform:6.9.22-patched             │
└─────────────────────────────────────────────────────────┘
```

**Điểm quan trọng:**
- Source code trong git **luôn sạch** — mọi patch chỉ xảy ra bên trong Docker build
- Chỉ build lại **backend** (~50s), không build frontend (tiết kiệm ~5 phút)
- Sửa code (AI, bug fix…) → chỉ cần `make patch && make restart`

---

## 3. Logic EE Bypass

OpenCTI có 2 file kiểm tra license Enterprise Edition:

| File | Chức năng gốc | Patch |
|------|---------------|-------|
| `ee.ts` | Kiểm tra license → cho/chặn feature EE | Ghi đè toàn bộ → luôn return `true` |
| `licensing.ts` | Parse license → trả về trạng thái | sed: `validated=true`, `expired=false`, `type=standard` |

Tất cả các chỗ gọi `checkEnterpriseEdition()` hay `isEnterpriseEdition()` trong codebase đều nhận được `true` → mọi feature EE đều mở.

---

## 4. Anthropic AI

OpenCTI gốc hỗ trợ: OpenAI, MistralAI, AzureOpenAI.

Fork này thêm **Anthropic Claude** bằng cách sửa 1 file: `ai-llm.ts`

- **Streaming** (AI Summary, Chatbot): Gọi trực tiếp Anthropic Messages API qua `fetch()` + SSE parsing
- **NLQ** (Natural Language Query): Dùng `@langchain/anthropic` SDK + monkey-patch xóa `top_p` (bug của SDK) + `bindTools()` thay vì `withStructuredOutput()` (vì Anthropic hay trả nested JSON string)
- Config qua biến môi trường trong `.env`: `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`

---

## 5. Commands thường dùng

```bash
make patch        # Build image (= docker compose build opencti)
make restart      # docker compose down + up
make logs         # Xem logs OpenCTI
make status       # Kiểm tra containers
make upgrade VERSION=6.10.0   # Đổi version + rebuild
```

Hoặc dùng Docker Compose trực tiếp:

```bash
docker compose build opencti    # Build
docker compose up -d            # Start
docker compose logs -f opencti  # Logs
```

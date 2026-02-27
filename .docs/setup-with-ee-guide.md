# OpenCTI Fork — Logic tổng quan

## 1. Kiến trúc repo

OpenCTI là **monorepo**, frontend + backend chung 1 repo:

```
opencti-platform/
├── opencti-graphql/    ← Backend (Node.js, TypeScript, GraphQL)
├── opencti-front/      ← Frontend (React, Relay)
└── opencti-dev/        ← Docker Compose cho dev (ES, Redis, RabbitMQ, MinIO)
```

---

## 2. Luồng build — Full Build từ source

Dockerfile hiện tại build **toàn bộ** (frontend + backend) từ source code, **không phụ thuộc image gốc** `opencti/platform`.

```
┌─────────────────────────────────────────────────────────┐
│ Bước 0: Patch source TRƯỚC khi build                    │
│                                                         │
│   ./patch_ee.sh      (hoặc make patch)                  │
│   → Sửa ee.ts + licensing.ts trực tiếp trên source     │
│   → Source trong git bị thay đổi (revert bằng --revert) │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────── docker compose build opencti ────────────┐
│                  (hoặc make build)                       │
│                                                         │
│  Stage 1: graphql-deps (node:22-alpine)                 │
│  └── yarn install → node_modules cho runtime            │
│                                                         │
│  Stage 2: graphql-builder (node:22-alpine)              │
│  └── COPY source (đã patch) → yarn build:prod           │
│      → Output: build/back.js                            │
│                                                         │
│  Stage 3: front-builder (node:22-alpine)                │
│  └── COPY opencti-front → yarn build:standalone         │
│      → Output: builder/prod/build/                      │
│                                                         │
│  Stage 4: app (node:22-alpine) — Runtime                │
│  └── COPY node_modules từ Stage 1                       │
│  └── COPY build/back.js từ Stage 2                      │
│  └── COPY frontend build từ Stage 3                     │
│  └── pip install python requirements                    │
│  └── CMD ["node", "build/back.js"]                      │
│                                                         │
│  → Image: opencti/platform:${VERSION}-custom            │
└─────────────────────────────────────────────────────────┘
```

**Điểm quan trọng:**
- **Patch chạy TRƯỚC build** — `patch_ee.sh` sửa source trực tiếp, Docker chỉ COPY và build
- **Build cả frontend + backend** từ source (~5-8 phút lần đầu, cache nhanh hơn)
- **Không phụ thuộc image gốc** — hoàn toàn self-contained, sẵn sàng cho RPM packaging
- Image tag: `opencti/platform:<version>-custom` (không phải `-patched`)

---

## 3. Logic EE Bypass (`patch_ee.sh`)

Script chạy **ngoài Docker**, sửa trực tiếp source code trước khi build:

```bash
./patch_ee.sh           # Patch source
./patch_ee.sh --check   # Kiểm tra đã patch chưa
./patch_ee.sh --revert  # Revert về bản gốc (git checkout)
```

| File | Chức năng gốc | Cách patch |
|------|---------------|------------|
| `ee.ts` | Kiểm tra license → cho/chặn feature EE | **Ghi đè toàn bộ file** → `isEnterpriseEdition()` luôn return `true` |
| `licensing.ts` | Parse license → trả về trạng thái | **sed** thay: `validated=true`, `valid_cert=true`, `expired=false`, `type=standard`, `global=true` |

> ⚠️ Sau khi patch, source code **bị thay đổi**. Revert bằng `./patch_ee.sh --revert` hoặc `make patch-revert`.

---

## 4. Anthropic AI

OpenCTI gốc hỗ trợ: OpenAI, MistralAI, AzureOpenAI.

Fork này thêm **Anthropic Claude** bằng cách sửa 1 file: `ai-llm.ts`

- **Streaming** (AI Summary, Chatbot): Gọi trực tiếp Anthropic Messages API qua `fetch()` + SSE parsing
- **NLQ** (Natural Language Query): Dùng `@langchain/anthropic` SDK + monkey-patch xóa `top_p` (bug của SDK) + `bindTools()` thay vì `withStructuredOutput()` (vì Anthropic hay trả nested JSON string)
- Config qua biến môi trường trong `.env`: `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`

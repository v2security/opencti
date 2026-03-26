# OpenCTI Infrastructure, Elasticsearch & Schema — Báo cáo kỹ thuật

> **Ngày**: 26/02/2026  
> **Version**: OpenCTI 6.9.22  
> **Tác giả**: Auto-generated từ source code analysis

---

## 1. Tổng quan kiến trúc

```
┌─────────────────────────────────────────────────────────────────┐
│                        CONNECTORS                               │
│  AlienVault │ MISP │ CVE │ MITRE │ Shodan │ Import/Export │ ... │
└──────┬──────┴──┬───┴──┬──┴───┬───┴────┬───┴───────┬───────┴─────┘
       │         │      │      │        │           │
       ▼         ▼      ▼      ▼        ▼           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    RabbitMQ (Message Broker)                    │
│  Exchange: opencti_push  │  Exchange: opencti_listen            │
│  Queue: push_<connector_id> per connector                       │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    WORKERS (Python × 3 replicas)                │
│  Push pool (2 threads) │ Realtime pool (3 threads)              │
│  Consume messages → Call GraphQL API → Ingest STIX bundles      │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              OpenCTI Platform (Node.js / GraphQL)               │
│                                                                 │
│  ┌──────────┐   ┌──────────┐  ┌──────────┐  ┌────────────────┐  │
│  │ GraphQL  │   │ STIX     │  │ Rule     │  │ Background     │  │
│  │ API      │   │ Ingestion│  │ Engine   │  │ Managers (15+) │  │
│  └────┬─────┘   └────┬─────┘  └────┬─────┘  └────────┬───────┘  │
│       │              │             │                 │          │
└───────┼──────────────┼─────────────┼─────────────────┼──────────┘
        │              │             │                 │
   ┌────▼─────┐   ┌────▼────┐   ┌────▼────┐       ┌────▼────┐
   │  Elastic │   │  Redis  │   │  MinIO  │       │ RabbitMQ│
   │  Search  │   │         │   │ (S3)    │       │         │
   └──────────┘   └─────────┘   └─────────┘       └─────────┘
```

### Vai trò từng component

| Component | Vai trò | Port |
|---|---|---|
| **Elasticsearch** | Database chính — lưu trữ & tìm kiếm toàn bộ entities, relationships | 8686 |
| **Redis** | Cache, live event stream, session, distributed lock, pub/sub | 6379 |
| **RabbitMQ** | Message queue — trung gian giữa connectors ↔ workers | 5672, 15672 |
| **MinIO** | Object storage (S3-compatible) — lưu file exports, attachments | 9000 |
| **Workers** | Consume messages từ RabbitMQ → gọi API để ingest STIX bundles | — |
| **XTM Composer** | Quản lý connectors qua Docker API | — |

---

## 2. Elasticsearch — Kiến trúc, Sharding & Auto-scaling

### 2.1 Cách OpenCTI tổ chức data trong ES

Tưởng tượng ES như một **tủ hồ sơ**. OpenCTI chia data thành **14 ngăn kéo (indices)**, mỗi ngăn chứa 1 loại hồ sơ:

```
📁 Entities (dữ liệu chính)
├── opencti_stix_domain_objects       ← INDEX LỚN NHẤT: Malware, Report, Indicator, Campaign...
├── opencti_stix_cyber_observables    ← INDEX LỚN THỨ 2: IP, Domain, File, URL, Hash...
├── opencti_stix_meta_objects         ← Nhỏ: Labels, Marking Definitions
├── opencti_internal_objects          ← Nhỏ: Users, Connectors, Settings
└── opencti_draft_objects             ← Draft workspace

📁 Relationships (quan hệ giữa entities)
├── opencti_stix_core_relationships   ← INDEX LỚN: "uses", "targets", "indicates"...
├── opencti_stix_meta_relationships   ← "created-by", "object-label"...
├── opencti_stix_sighting_relationships
└── opencti_internal_relationships

📁 Inference (data tự sinh từ Rule Engine)
├── opencti_inferred_entities
└── opencti_inferred_relationships

📁 System
├── opencti_history                   ← Audit logs
├── opencti_deleted_objects           ← Thùng rác
└── opencti_files                     ← File metadata
```

**Tại sao không 1 index cho mỗi entity type?** Vì OpenCTI có ~60 entity types. 60 indices × shards × replicas = quá nhiều shard, gây overhead cho cluster. Gom theo category giữ số index nhỏ, ES quản lý hiệu quả hơn.

**Tại sao không time-based index?** Vì threat intelligence không phải log — data cần update liên tục (enrich, merge, decay score), không phải append-only.

### 2.2 Sharding — Chia nhỏ index để phân tán

Mỗi index được chia thành **shards** (mảnh). Shard là đơn vị nhỏ nhất mà ES phân tán trên các nodes.

```
                    opencti_stix_domain_objects (index)
                    ┌─────────┬─────────┬─────────┐
                    │ Shard 0 │ Shard 1 │ Shard 2 │  ← Primary shards (data gốc)
                    └────┬────┴────┬────┴────┬────┘
                         │         │         │
        ┌────────────────┼─────────┼─────────┼────────────────┐
        │    ES Node 1   │  ES Node 2        │   ES Node 3    │
        │  ┌─────────┐   │  ┌─────────┐      │  ┌─────────┐   │
        │  │ Shard 0 │   │  │ Shard 1 │      │  │ Shard 2 │   │
        │  │(primary)│   │  │(primary)│      │  │(primary)│   │
        │  ├─────────┤   │  ├─────────┤      │  ├─────────┤   │
        │  │ Shard 2 │   │  │ Shard 0 │      │  │ Shard 1 │   │
        │  │(replica)│   │  │(replica)│      │  │(replica)│   │
        │  └─────────┘   │  └─────────┘      │  └─────────┘   │
        └────────────────┴───────────────────┴────────────────┘
```

### 2.3 Auto-scaling — ILM Rollover (tự tách index khi quá lớn)

Đây là cơ chế **tự động scale** quan trọng nhất. Khi 1 index quá lớn, OpenCTI tự tạo index mới:

```
Ban đầu:
  opencti_stix_domain_objects (alias) ──write──▶ opencti_stix_domain_objects-000001

Khi -000001 đạt 50GB hoặc 75M documents:
  ES tự động:
  1. Tạo opencti_stix_domain_objects-000002
  2. Chuyển alias write sang -000002
  3. -000001 thành read-only

  opencti_stix_domain_objects (alias) ──write──▶ opencti_stix_domain_objects-000002 (mới)
  opencti_stix_domain_objects* ──read──▶ -000001 + -000002 (tất cả)

Tiếp tục khi -000002 đầy:
  opencti_stix_domain_objects (alias) ──write──▶ opencti_stix_domain_objects-000003
  opencti_stix_domain_objects* ──read──▶ -000001 + -000002 + -000003
```

**Rollover triggers** (chạm 1 trong 2 là rollover):

| Trigger | Giá trị mặc định | Config |
|---|---|---|
| Primary shard ≥ | **50 GB** | `ELASTICSEARCH__MAX_PRIMARY_SHARD_SIZE` |
| Số documents ≥ | **75,000,000** | `ELASTICSEARCH__MAX_DOCS` |

**Kỹ thuật bên trong:**
- OpenCTI tạo **ILM policy** (ELK) hoặc **ISM policy** (OpenSearch) khi khởi động
- Policy chỉ có **hot phase** — không có warm/cold/delete (vì CTI data cần truy cập nhanh mãi)
- Mỗi index template gắn với ILM policy qua `rollover_alias`

> **Source code**: `opencti-platform/opencti-graphql/src/database/engine.ts`

### 2.4 Toàn bộ flow khởi tạo ES

Khi platform start, nó thực hiện đúng thứ tự:

```
1. updateCoreSettings()
   └── Tạo Component Template "opencti-core-settings"
       ├── number_of_shards: <từ config>
       ├── number_of_replicas: <từ config>
       ├── max_result_window: 100,000
       └── string_normalizer: lowercase + asciifolding

2. elCreateLifecyclePolicy()
   └── Tạo ILM Policy "opencti-ilm-policy"
       └── hot phase: rollover khi shard ≥ 50GB hoặc docs ≥ 75M

3. Cho mỗi index trong 14 indices:
   ├── elCreateIndexTemplate(index)
   │   └── Tạo Index Template kế thừa từ "opencti-core-settings"
   │       ├── mapping: dynamic=strict (không auto-detect field)
   │       ├── total_fields.limit: 3,000
   │       └── lifecycle: gắn ILM policy + rollover_alias
   │
   └── elCreateIndex(index)
       └── Tạo index "opencti_xxx-000001" với alias "opencti_xxx"
```

### 2.5 Tối ưu query — Không search tất cả indices

Khi query, hệ thống chỉ search đúng indices cần thiết:

| Query | Indices được search | Thay vì |
|---|---|---|
| Tìm `Malware` | `stix_domain_objects*` (1 index) | 14 indices |
| Tìm `IPv4` | `stix_cyber_observables*` (1 index) | 14 indices |
| Tìm tất cả entities | 5 entity indices | 14 indices |
| Tìm relationships | 6 relationship indices | 14 indices |

### 2.6 Tham số cấu hình ES đầy đủ

| Parameter | Config key | Env var | Default | Mô tả |
|---|---|---|---|---|
| Shards | `elasticsearch.number_of_shards` | `ELASTICSEARCH__NUMBER_OF_SHARDS` | 1 (ES default) | Số mảnh per index |
| Replicas | `elasticsearch.number_of_replicas` | `ELASTICSEARCH__NUMBER_OF_REPLICAS` | 1 (ES default) | Số bản sao per shard |
| Rollover shard size | `elasticsearch.max_primary_shard_size` | `ELASTICSEARCH__MAX_PRIMARY_SHARD_SIZE` | **50gb** | Trigger tách index |
| Rollover doc count | `elasticsearch.max_docs` | `ELASTICSEARCH__MAX_DOCS` | **75,000,000** | Trigger tách index |
| Max result window | `elasticsearch.max_result_window` | `ELASTICSEARCH__MAX_RESULT_WINDOW` | 100,000 | Giới hạn pagination |
| Max field mappings | Hardcoded | — | 3,000 | Giới hạn số fields per index |
| Max concurrency | `elasticsearch.max_concurrency` | `ELASTICSEARCH__MAX_CONCURRENCY` | 4 | Số ES operations song song |
| Bulk batch size | `elasticsearch.max_bulk_operations` | `ELASTICSEARCH__MAX_BULK_OPERATIONS` | 5,000 | Batch size bulk indexing |
| Index prefix | `elasticsearch.index_prefix` | `ELASTICSEARCH__INDEX_PREFIX` | `opencti` | Prefix tên index |

### 2.7 Scale theo quy mô — Nên config thế nào?

| Quy mô | Entities | Shards/index | Replicas | ES Nodes | Heap | Storage |
|---|---|---|---|---|---|---|
| **Dev/Lab** (hiện tại) | < 500K | 1 | 0 | 1 | 4GB | 50GB |
| **Small production** | 500K - 5M | 1-2 | 1 | 3 | 8GB | 200GB |
| **Medium production** | 5M - 20M | 3 | 1 | 3-5 | 16GB | 500GB |
| **Large production** | 20M+ | 5 | 1-2 | 5+ | 32GB | 1TB+ |

**Quy tắc vàng:**
- **1 shard nên chứa 20-50GB data** → nếu `stix_domain_objects` dự kiến 100GB → set 3-5 shards
- **Heap ES ≤ 50% RAM** và **không quá 32GB** (compressed oops threshold)
- **Replicas ≥ 1** khi chạy production (chịu lỗi 1 node)
- **Tổng shards trên cluster** nên < 20 shards per GB heap (ví dụ 16GB heap → < 320 shards)

---

-- Migration: 003_add_opencti_cursor_fields
-- Description: Add opencti_id and opencti_created_at to support
--              Elasticsearch cursor pagination (sort: [created_at, _id])
--
-- Rationale:
--   cursor pagination cần sort trên 2 trường:
--     - created_at  → thứ tự thời gian
--     - _id         → tie-breaker khi nhiều record cùng timestamp
--   Lưu cả hai vào MySQL để:
--     1. Biết mỗi row đến từ entity nào trong OpenCTI (traceability)
--     2. Resume sync chính xác bằng search_after: [opencti_created_at, opencti_id]
--     3. Deduplicate: cùng opencti_id → cùng entity, chỉ cần update

-- ── ids_blacklist ────────────────────────────────────────────────────────

ALTER TABLE `ids_blacklist`
    ADD COLUMN `opencti_id`         VARCHAR(255) NULL DEFAULT NULL COMMENT 'OpenCTI standard_id (STIX id) for traceability and cursor resume' AFTER `id`,
    ADD COLUMN `opencti_created_at` DATETIME     NULL DEFAULT NULL COMMENT 'Entity created_at in OpenCTI — cursor pagination sort field' AFTER `opencti_id`,
    ADD INDEX  `idx_cursor`         (`opencti_created_at`, `opencti_id`);

-- ── hashlist ─────────────────────────────────────────────────────────────

ALTER TABLE `hashlist`
    ADD COLUMN `opencti_id`         VARCHAR(255) NULL DEFAULT NULL COMMENT 'OpenCTI standard_id (STIX id) for traceability and cursor resume' AFTER `id`,
    ADD COLUMN `opencti_created_at` DATETIME     NULL DEFAULT NULL COMMENT 'Entity created_at in OpenCTI — cursor pagination sort field' AFTER `opencti_id`,
    ADD INDEX  `idx_cursor`         (`opencti_created_at`, `opencti_id`);

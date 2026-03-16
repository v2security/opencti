-- Migration: 002_hashlist
-- Description: Create hashlist table for file hash IOC (MD5)
-- Source: FR-01__Design.md schema from TI Server (163.223.58.154)

CREATE TABLE IF NOT EXISTS `hashlist` (
    `id`                 INT          NOT NULL AUTO_INCREMENT,
    `opencti_id`         VARCHAR(255) NULL DEFAULT NULL COMMENT 'OpenCTI standard_id (STIX id) for traceability and cursor resume',
    `opencti_created_at` DATETIME     NULL DEFAULT NULL COMMENT 'Entity created_at in OpenCTI — cursor pagination sort field',
    `description`        TINYTEXT     NOT NULL COMMENT 'AV vendor or detection source: Kaspersky, FireEye, Sophos, etc.',
    `name`               TINYTEXT     NOT NULL COMMENT 'Malware family / detection name',
    `value`              VARCHAR(64)  NOT NULL COMMENT 'File hash: MD5(32), SHA-1(40), SHA-256(64)',
    `type`               TINYTEXT     NOT NULL COMMENT 'Scope: global or local',
    `version`            TINYTEXT     NOT NULL COMMENT 'Version timestamp: YYYYMMDDHHmmss',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_value` (`value`),
    INDEX `idx_cursor` (`opencti_created_at`, `opencti_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

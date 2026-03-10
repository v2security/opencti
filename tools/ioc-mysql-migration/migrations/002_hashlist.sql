-- Migration: 002_hashlist
-- Description: Create hashlist table for file hash IOC (MD5)
-- Source: FR-01__Design.md schema from TI Server (163.223.58.154)

CREATE TABLE IF NOT EXISTS `hashlist` (
    `id`          INT          NOT NULL AUTO_INCREMENT,
    `description` TINYTEXT     NOT NULL COMMENT 'AV vendor or detection source: Kaspersky, FireEye, Sophos, etc.',
    `name`        TINYTEXT     NOT NULL COMMENT 'Malware family / detection name',
    `value`       VARCHAR(64)  NOT NULL COMMENT 'File hash: MD5(32), SHA-1(40), SHA-256(64)',
    `type`        TINYTEXT     NOT NULL COMMENT 'Scope: global or local',
    `version`     TINYTEXT     NOT NULL COMMENT 'Version timestamp: YYYYMMDDHHmmss',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_value` (`value`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

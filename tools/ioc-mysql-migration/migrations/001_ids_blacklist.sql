-- Migration: 001_ids_blacklist
-- Description: Create ids_blacklist table for IP/Domain IOC blacklist
-- Source: FR-01__Design.md schema from TI Server (163.223.58.154)

CREATE TABLE IF NOT EXISTS `ids_blacklist` (
    `id`      INT          NOT NULL AUTO_INCREMENT,
    `stype`   TINYTEXT     NOT NULL COMMENT 'IOC type: ip, domain',
    `value`   VARCHAR(255) NOT NULL COMMENT 'IOC value: IP address or domain name',
    `country` TINYTEXT     NOT NULL COMMENT 'Country of origin (or "none")',
    `source`  TINYTEXT     NOT NULL COMMENT 'Threat source: malware, phishing, etc.',
    `srctype` TINYTEXT     NOT NULL COMMENT 'Source type: v2, etc.',
    `type`    TINYTEXT     NOT NULL COMMENT 'Scope: local or global',
    `version` TINYTEXT     NOT NULL COMMENT 'Version timestamp: YYYYMMDDHHmmss',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_value` (`value`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

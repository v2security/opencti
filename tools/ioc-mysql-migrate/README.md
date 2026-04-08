# ioc-mysql-migrate — MySQL Schema Migration

Tạo và quản lý schema MySQL cho các bảng IOC (`ids_blacklist`, `hashlist`).

## Project Structure

```
ioc-mysql-migrate/
├── main.go                         # Entry point — run migrations
├── Makefile                        # Build + DB helper commands
├── migrations/
│   ├── 001_ids_blacklist.sql       # Create ids_blacklist table
│   └── 002_hashlist.sql            # Create hashlist table
├── .env                            # Config (MySQL credentials)
├── go.mod / go.sum
└── deploy/
    └── v2-ioc-migrate              # Binary (built by make)
```

## Flow

```
1. Load .env (same dir as binary + cwd)
2. Connect MySQL
3. Create _migrations tracking table (if not exists)
4. Read embedded migrations/*.sql (go:embed, sorted by filename)
5. Skip already-applied migrations
6. Execute new migrations + record in _migrations
```

SQL migrations are embedded into the binary via `go:embed` — chỉ cần deploy 1 file binary + `.env`, không cần kèm thư mục `migrations/`.

## Tables

### ids_blacklist

| Column             | Type         | Description                              |
|--------------------|--------------|------------------------------------------|
| id                 | INT PK       | Auto-increment                           |
| opencti_id         | VARCHAR(255) | OpenCTI standard_id (STIX id)            |
| opencti_created_at | DATETIME     | Entity created_at — cursor pagination    |
| stype              | TINYTEXT     | IOC type: ip, domain                     |
| value              | VARCHAR(255) | IOC value (unique)                       |
| country            | TINYTEXT     | Country of origin                        |
| source             | TINYTEXT     | Threat source: malware, suspicious, etc. |
| srctype            | TINYTEXT     | Source type: v2                          |
| type               | TINYTEXT     | Scope: local or global                   |
| version            | TINYTEXT     | Version timestamp: YYYYMMDDHHmmss        |

### hashlist

| Column             | Type         | Description                              |
|--------------------|--------------|------------------------------------------|
| id                 | INT PK       | Auto-increment                           |
| opencti_id         | VARCHAR(255) | OpenCTI standard_id (STIX id)            |
| opencti_created_at | DATETIME     | Entity created_at — cursor pagination    |
| description        | TINYTEXT     | AV vendor: Kaspersky, FireEye, etc.      |
| name               | TINYTEXT     | Malware family / detection name          |
| value              | VARCHAR(64)  | File hash: MD5/SHA-1/SHA-256 (unique)    |
| type               | TINYTEXT     | Scope: global or local                   |
| version            | TINYTEXT     | Version timestamp: YYYYMMDDHHmmss        |

## Build & Deploy

```bash
# 1. Config
cp .env.sample .env    # hoặc edit .env trực tiếp
vi .env                 # fill MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE

# 2. Build → deploy/
make build
# Output: deploy/v2-ioc-migrate

# 3. Run migrations
deploy/v2-ioc-migrate

# 4. Verify
make describe           # show table schemas
make sample             # show first 10 rows
```

### Deploy lên server

```bash
cp deploy/v2-ioc-migrate /opt/tools/
/opt/tools/v2-ioc-migrate
```

## Environment Variables

| Variable       | Required | Default     | Description          |
|----------------|----------|-------------|----------------------|
| MYSQL_HOST     | No       | 127.0.0.1   | MySQL host           |
| MYSQL_PORT     | No       | 3306        | MySQL port           |
| MYSQL_USER     | Yes      | —           | MySQL user           |
| MYSQL_PASSWORD | Yes      | —           | MySQL password       |
| MYSQL_DATABASE | Yes      | —           | MySQL database name  |

## Makefile Targets

```bash
make build      # Build binary → deploy/v2-ioc-migrate
make describe   # Show table schemas (DESCRIBE)
make sample     # Show first 10 rows of each table
make check      # Show indexes + row counts
make status     # Show migration history
```

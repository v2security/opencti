include .env

MYSQL_HOST   ?= 127.0.0.1
MYSQL_PORT   ?= 3306
MYSQL_USER   ?= root
MYSQL_PASS   := $(MYSQL_ROOT_PASSWORD)
DB           := $(MYSQL_DATABASE)
MYSQL_CMD    := mysql -h $(MYSQL_HOST) -P $(MYSQL_PORT) -u $(MYSQL_USER) -p$(MYSQL_PASS) $(DB)

.PHONY: migrate describe check help

## Run all migrations
migrate:
	source .env && go run main.go

## Show table schemas
describe:
	@echo "=== ids_blacklist ==="
	@$(MYSQL_CMD) -e "DESCRIBE ids_blacklist;" 2>/dev/null || echo "(table not found)"
	@echo ""
	@echo "=== hashlist ==="
	@$(MYSQL_CMD) -e "DESCRIBE hashlist;" 2>/dev/null || echo "(table not found)"

## Show indexes + row counts
check:
	@echo "=== ids_blacklist ==="
	@$(MYSQL_CMD) -e "SHOW INDEX FROM ids_blacklist; SELECT COUNT(*) AS total FROM ids_blacklist;" 2>/dev/null || echo "(table not found)"
	@echo ""
	@echo "=== hashlist ==="
	@$(MYSQL_CMD) -e "SHOW INDEX FROM hashlist; SELECT COUNT(*) AS total FROM hashlist;" 2>/dev/null || echo "(table not found)"

## Show migration history
status:
	@$(MYSQL_CMD) -e "SELECT * FROM _migrations ORDER BY id;" 2>/dev/null || echo "(no migrations table)"

## Run migrate then describe
all: migrate describe

help:
	@echo "make migrate   — run migrations"
	@echo "make describe  — DESCRIBE both tables"
	@echo "make check     — show indexes + row counts"
	@echo "make status    — show applied migrations"
	@echo "make all       — migrate + describe"

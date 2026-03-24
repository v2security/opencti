###############################################################################
# OpenCTI Platform - Makefile
#
# make start / stop           → Stack chính (infra + opencti + worker)
###############################################################################

include .env
export

.PHONY: help start stop restart \
        upgrade build patch patch-check patch-revert \
        status logs logs-worker health \
        clean destroy info prune

## ─── STACK CHÍNH ─────────────────────────
env: 
	cp .env /etc/saids/opencti
	cp .env opencti-deploy-offline/config
	cp .env.example /etc/saids/opencti
	cp .env.example opencti-deploy-offline/config

start: ## Start stack (infra + opencti + worker)
	docker compose up -d

stop: ## Stop stack
	docker compose down

restart: ## Restart stack
	docker compose down && docker compose up -d

## ─── UPGRADE & BUILD ─────────────────────
upgrade: ## Patch → build → restart tất cả
	./patch_ee.sh
	docker compose build opencti
	docker compose down
	docker compose up -d

build: ## Build image opencti
	docker compose build opencti

patch: ## Patch EE source
	./patch_ee.sh

patch-check: ## Kiểm tra đã patch chưa
	./patch_ee.sh --check

patch-revert: ## Revert patch
	./patch_ee.sh --revert

## ─── MONITORING ──────────────────────────
status: ## Trạng thái tất cả containers
	@docker compose ps

logs: ## Logs opencti (follow)s
	docker compose logs -f opencti

logs-worker: ## Logs worker
	docker compose logs -f worker

health: ## Health check
	@curl -s "http://localhost:$(APP_PORT)/health?health_access_key=$(APP_HEALTH_ACCESS_KEY)" | python3 -m json.tool 2>/dev/null || echo "Chưa sẵn sàng"

## ─── CLEANUP ─────────────────────────────

clean: ## Xóa dangling images + build cache
	docker image prune -f && docker builder prune -f

destroy: ## Xóa tất cả + volumes (⚠️ MẤT DATA)
	@read -p "⚠️  Xóa hết data? (y/N): " c && [ "$$c" = "y" ] || exit 1
	docker compose down -v

prune: ## Xóa tất cả unused images
	docker image prune -a -f

## ─── INFO ────────────────────────────────

info: ## Thông tin OpenCTI
	@echo "Version: $(OPENCTI_VERSION) | URL: $(APP_BASE_URL)"
	@echo "Admin: $(APP_ADMIN_EMAIL) | Password: $(APP_ADMIN_PASSWORD)"
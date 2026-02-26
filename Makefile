###############################################################################
# OpenCTI Platform - Makefile
#
# Tất cả commands quản lý OpenCTI từ một chỗ.
#
# Sử dụng:
#   make help                      # Xem danh sách commands
#   make upgrade VERSION=6.10.0    # Nâng cấp lên version mới
#   make restart                   # Restart toàn bộ
#   make logs                      # Xem logs
###############################################################################

# Load version from .env
include .env
export

# Default version (fallback)
VERSION ?= $(OPENCTI_VERSION)

.PHONY: prune help upgrade patch patch-check patch-revert build up down restart status logs logs-opencti \
        logs-worker ps clean version start stop

prune:
	docker image prune -a -f

## ─────────────────────────────────────────
## 📋 HELP
## ─────────────────────────────────────────

help: ## Hiển thị danh sách commands
	@echo ""
	@echo "╔══════════════════════════════════════════════════╗"
	@echo "║        OpenCTI Platform - Commands               ║"
	@echo "║        Current version: $(OPENCTI_VERSION)       ║"
	@echo "╚══════════════════════════════════════════════════╝"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""

## ─────────────────────────────────────────
## 🚀 UPGRADE (patch + build + restart)
## ─────────────────────────────────────────

upgrade: ## Nâng cấp: patch source → build image → restart
	@echo "🚀 Upgrading OpenCTI..."
	./patch_ee.sh
	docker compose build opencti
	docker compose down
	docker compose up -d
	@echo "✅ Done! Run 'make logs' to check"

## ─────────────────────────────────────────
## 🔧 PATCH & BUILD (từng bước)
## ─────────────────────────────────────────

patch: ## Patch EE trên source code (sed trực tiếp)
	./patch_ee.sh

patch-check: ## Kiểm tra source đã patch chưa
	./patch_ee.sh --check

patch-revert: ## Revert source về git HEAD
	./patch_ee.sh --revert

build: ## Build Docker image từ source (đã patch)
	docker compose build opencti

## ─────────────────────────────────────────
## 🐳 DOCKER COMPOSE
## ─────────────────────────────────────────

up: ## Start tất cả containers
start: ## Start tất cả containers (alias)
up start:
	docker compose up -d

down: ## Stop tất cả containers
stop: ## Stop tất cả containers (alias)
down stop:
	docker compose down

restart: ## Restart toàn bộ (down + up)
	docker compose down
	docker compose up -d

restart-opencti: ## Restart chỉ OpenCTI platform
	docker compose restart opencti

## ─────────────────────────────────────────
## 📊 MONITORING
## ─────────────────────────────────────────

status: ## Kiểm tra trạng thái containers
	@echo ""
	@echo "Version: $(OPENCTI_VERSION)"
	@echo ""
	@docker compose ps
	@echo ""
	@echo "Images:"
	@docker images | grep -E 'opencti|REPOSITORY' | head -10

ps: ## Docker ps format đẹp
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -E 'opencti|NAMES'

logs: ## Xem logs OpenCTI platform (follow)
	docker compose logs -f opencti

logs-worker: ## Xem logs workers
	docker compose logs -f worker

logs-all: ## Xem logs tất cả services
	docker compose logs -f

health: ## Kiểm tra health endpoint
	@curl -s "http://localhost:$(OPENCTI_PORT)/health?health_access_key=$(OPENCTI_HEALTHCHECK_ACCESS_KEY)" | python3 -m json.tool 2>/dev/null || echo "OpenCTI chưa sẵn sàng"

## ─────────────────────────────────────────
## 🧹 CLEANUP
## ─────────────────────────────────────────

clean: ## Xóa dangling images và build cache
	docker image prune -f
	docker builder prune -f

clean-all: ## Xóa tất cả custom images cũ
	@echo "Removing old custom images..."
	@docker images | grep -E 'patched|custom' | awk '{print $$3}' | xargs -r docker rmi -f 2>/dev/null || true
	@echo "Done."

## ─────────────────────────────────────────
## ℹ️  INFO
## ─────────────────────────────────────────

version: ## Hiển thị version hiện tại
	@echo "OPENCTI_VERSION=$(OPENCTI_VERSION)"
	@echo "Image: opencti/platform:$(OPENCTI_VERSION)-custom"

info: ## Hiển thị thông tin chi tiết
	@echo ""
	@echo "OpenCTI Platform Info"
	@echo "─────────────────────────────────────────"
	@echo "Version     : $(OPENCTI_VERSION)"
	@echo "URL         : $(OPENCTI_EXTERNAL_SCHEME)://$(OPENCTI_HOST):$(OPENCTI_PORT)"
	@echo "Admin       : $(OPENCTI_ADMIN_EMAIL)"
	@echo "AI Enabled  : true"
	@echo "AI Provider : $(AI_TYPE)"
	@echo "AI Model    : $(AI_MODEL)"
	@echo "─────────────────────────────────────────"
	@echo ""

.PHONY: start stop restart
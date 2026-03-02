# ══════════════════════════════════════════════════════════════
# OpenCTI Offline Deployment — Build & Test
# ══════════════════════════════════════════════════════════════
#
# Workflow:
#   make package   — Đóng gói offline (cần Docker + internet)
#   make test      — Test cài đặt trong Rocky 9 container
#
# Mount paths (docker-compose.yml):
#   ./output  →  /root/opencti-deploy   (package files)
#
# Build output:
#   opencti-offline-deploy.tar.gz (~1.2GB)
#   output/
#   ├── files/
#   │   ├── opencti.tar.gz              ← Platform (Node.js + rebuilt native module)
#   │   ├── opencti-worker.tar.gz       ← Worker (Python + wheels)
#   │   ├── python312.tar.gz            ← Python 3.12.8 compiled
#   │   ├── elasticsearch-*.tar.gz      ← Elasticsearch 8.17.0
#   │   ├── rabbitmq-server-*.tar.xz    ← RabbitMQ 4.1.0
#   │   ├── minio                       ← MinIO binary
#   │   └── mc                          ← MinIO client
#   ├── rpm/    ← Node.js 22, Redis, Erlang, system deps
#   ├── config/ ← systemd services, start.sh, ES/RabbitMQ configs
#   └── scripts/← deploy-offline.sh, uninstall-opencti.sh
#
# Deploy trên máy đích:
#   tar -xzf opencti-offline-deploy.tar.gz
#   cd opencti-deploy && bash scripts/deploy-offline.sh
# ══════════════════════════════════════════════════════════════

COMPOSE   := docker compose
CONTAINER := opencti-rocky9-test

.PHONY: test package build up down exec deploy uninstall status logs logs-worker logs-es clean destroy help
.DEFAULT_GOAL := help

help: ## Hiển thị help
	@echo ""
	@echo "  OpenCTI Offline Deployment"
	@echo "  ═══════════════════════════"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ── Main workflow ─────────────────────────────────────────────

test: ## Full test: build → deploy → status (trong Rocky 9 container)
	@echo ""
	@echo "══════════════════════════════════════════"
	@echo "  TEST: Rocky 9 container"
	@echo "  Mount: ./output → /root/opencti-deploy"
	@echo "══════════════════════════════════════════"
	$(COMPOSE) down -v 2>/dev/null || true
	$(COMPOSE) build
	$(COMPOSE) up -d
	@echo "⏳ Đợi systemd..."
	@docker exec $(CONTAINER) bash -c \
		'for i in $$(seq 1 30); do systemctl is-system-running 2>/dev/null | grep -qE "running|degraded" && break; sleep 1; done'
	@echo "▸ Chạy deploy-offline.sh..."
	docker exec $(CONTAINER) bash -c 'cd /root/opencti-deploy && bash scripts/deploy-offline.sh'
	@$(MAKE) --no-print-directory status

package: ## Đóng gói offline package → opencti-offline-deploy.tar.gz
	bash scripts/package-for-offline.sh

# ── Container ─────────────────────────────────────────────────

build: ## Build Rocky 9 test container
	$(COMPOSE) build

up: ## Start test container
	$(COMPOSE) up -d

down: ## Stop test container
	$(COMPOSE) down

exec: ## Shell vào container
	docker exec -it $(CONTAINER) bash

# ── Deploy & manage ───────────────────────────────────────────

deploy: ## Chạy deploy-offline.sh trong container
	@docker exec $(CONTAINER) bash -c \
		'for i in $$(seq 1 30); do systemctl is-system-running 2>/dev/null | grep -qE "running|degraded" && break; sleep 1; done'
	docker exec $(CONTAINER) bash -c 'cd /root/opencti-deploy && bash scripts/deploy-offline.sh'

uninstall: ## Gỡ cài đặt trong container
	docker exec -it $(CONTAINER) bash -c 'cd /root/opencti-deploy && bash scripts/uninstall-opencti.sh'

status: ## Kiểm tra services status
	@echo ""
	@echo "  📊 Service Status"
	@echo "  ════════════════════"
	@docker exec $(CONTAINER) bash -c '\
		for svc in elasticsearch redis rabbitmq-server minio opencti; do \
			STATUS=$$(systemctl is-active $$svc 2>/dev/null || echo inactive); \
			if [ "$$STATUS" = "active" ]; then \
				printf "  ✅ %-20s %s\n" "$$svc" "$$STATUS"; \
			else \
				printf "  ❌ %-20s %s\n" "$$svc" "$$STATUS"; \
			fi; \
		done; \
		for i in 1 2 3; do \
			STATUS=$$(systemctl is-active opencti-worker@$$i 2>/dev/null || echo inactive); \
			if [ "$$STATUS" = "active" ]; then \
				printf "  ✅ %-20s %s\n" "worker@$$i" "$$STATUS"; \
			else \
				printf "  ❌ %-20s %s\n" "worker@$$i" "$$STATUS"; \
			fi; \
		done; \
		echo ""; \
		echo "  🌐 Ports:"; \
		ss -tlnp 2>/dev/null | grep -E "8443|9200|6379|5672|15672|9000|9001" | \
			sed "s/^/    /" || true; \
		echo ""; \
		echo "  🔗 Health check:"; \
		curl -sf -k https://localhost:8443/health && echo "  ✅ OpenCTI OK" || echo "  ⏳ OpenCTI chưa ready"; \
	'

# ── Logs ──────────────────────────────────────────────────────

logs: ## Platform logs
	docker exec $(CONTAINER) journalctl -u opencti -f --no-pager

logs-worker: ## Worker logs
	docker exec $(CONTAINER) journalctl -u 'opencti-worker@*' -f --no-pager

logs-es: ## Elasticsearch logs
	docker exec $(CONTAINER) journalctl -u elasticsearch -f --no-pager

# ── Cleanup ───────────────────────────────────────────────────

clean: ## Xóa container + images
	$(COMPOSE) down --rmi local 2>/dev/null || true

destroy: ## Xóa TẤT CẢ (container + images + volumes + output)
	$(COMPOSE) down -v --rmi local 2>/dev/null || true
	docker run --rm -v "$(CURDIR)/output:/d" alpine chown -R $$(id -u):$$(id -g) /d 2>/dev/null || true
	rm -rf output/
	rm -f opencti-offline-deploy.tar.gz
	docker rmi opencti-offline-builder:latest rockylinux-node22 2>/dev/null || true
	docker volume prune -f 2>/dev/null || true
	@echo "✓ Đã xóa tất cả"

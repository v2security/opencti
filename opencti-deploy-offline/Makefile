# ══════════════════════════════════════════════════════════════
# Infrastructure Test — MinIO + Redis + RabbitMQ
# ══════════════════════════════════════════════════════════════
#
# Test 3 infrastructure services trong Rocky Linux 9 container
# với systemd.
#
# Usage:
#   make test        # Full: build → start → deploy → status
#   make build up    # Chỉ start container
#   make deploy      # Chạy setup_infra.sh
#   make status      # Kiểm tra services
#   make exec        # Shell vào container
#   make destroy     # Xóa tất cả
# ══════════════════════════════════════════════════════════════

COMPOSE   := docker compose
CONTAINER := opencti-infra-test

.PHONY: test build up down exec deploy status logs clean destroy help
.DEFAULT_GOAL := help

help: ## Hiển thị help
	@echo ""
	@echo "  Infrastructure Test — MinIO + Redis + RabbitMQ"
	@echo "  ═══════════════════════════════════════════════"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ── Main workflow ─────────────────────────────────────────────

test: build up deploy status ## Full test: build → deploy → status
	@echo ""
	@echo "  ✅ Infrastructure test complete!"
	@echo ""

build: ## Build Rocky 9 test container
	$(COMPOSE) build

up: ## Start test container
	$(COMPOSE) up -d
	@echo "⏳ Waiting for systemd..."
	@docker exec $(CONTAINER) bash -c \
		'for i in $$(seq 1 30); do systemctl is-system-running 2>/dev/null | grep -qE "running|degraded" && break; sleep 1; done'
	@echo "✓ Systemd ready"

down: ## Stop test container
	$(COMPOSE) down

exec: ## Shell vào container
	docker exec -it $(CONTAINER) bash

deploy: ## Chạy setup_infra.sh trong container
	docker exec $(CONTAINER) bash /root/opencti-deploy/infra/setup_infra.sh

status: ## Kiểm tra services status
	@echo ""
	@echo "  📊 Infrastructure Service Status"
	@echo "  ════════════════════════════════════════"
	@docker exec $(CONTAINER) bash -c '\
		for svc in redis minio rabbitmq-server; do \
			STATUS=$$(systemctl is-active $$svc 2>/dev/null || echo inactive); \
			if [ "$$STATUS" = "active" ]; then \
				printf "  ✅ %-20s %s\n" "$$svc" "$$STATUS"; \
			else \
				printf "  ❌ %-20s %s\n" "$$svc" "$$STATUS"; \
			fi; \
		done; \
		echo ""; \
		echo "  🌐 Listening Ports:"; \
		ss -tlnp 2>/dev/null | grep -E "6379|9000|9001|5672|15672" | \
			sed "s/^/    /" || echo "    (no ports found)"; \
		echo ""; \
		echo "  🔍 Health Checks:"; \
		RPASS=$$(sed -n "s/^requirepass //p" /etc/redis/redis.conf 2>/dev/null || true); \
		redis-cli -p 6379 $${RPASS:+-a "$$RPASS" --no-auth-warning} ping 2>/dev/null | grep -q PONG && \
			echo "    ✅ Redis: PONG" || echo "    ❌ Redis: no response"; \
		curl -sf http://localhost:9000/minio/health/live && \
			echo "    ✅ MinIO: healthy" || echo "    ❌ MinIO: no response"; \
		RABBITMQ_CONF_ENV_FILE=/etc/rabbitmq/rabbitmq-env.conf rabbitmqctl status &>/dev/null && \
			echo "    ✅ RabbitMQ: running" || echo "    ❌ RabbitMQ: no response"; \
		echo ""; \
	'

# ── Logs ──────────────────────────────────────────────────────

logs: ## Show all infra logs
	docker exec $(CONTAINER) bash -c '\
		echo "═══ Redis (/var/log/redis/) ═══"; \
		tail -15 /var/log/redis/redis.log 2>/dev/null || journalctl -u redis -n 15 --no-pager 2>/dev/null || true; \
		echo ""; \
		echo "═══ MinIO (/var/log/minio/) ═══"; \
		tail -15 /var/log/minio/minio.log 2>/dev/null || journalctl -u minio -n 15 --no-pager 2>/dev/null || true; \
		echo ""; \
		echo "═══ RabbitMQ (/var/log/rabbitmq/) ═══"; \
		tail -15 /var/log/rabbitmq/*.log 2>/dev/null || journalctl -u rabbitmq-server -n 15 --no-pager 2>/dev/null || true; \
	'

logs-redis: ## Redis logs
	docker exec $(CONTAINER) bash -c 'tail -f /var/log/redis/redis.log 2>/dev/null || journalctl -u redis -f --no-pager'

logs-minio: ## MinIO logs
	docker exec $(CONTAINER) bash -c 'tail -f /var/log/minio/minio.log 2>/dev/null || journalctl -u minio -f --no-pager'

logs-rabbitmq: ## RabbitMQ logs
	docker exec $(CONTAINER) bash -c 'tail -f /var/log/rabbitmq/*.log 2>/dev/null || journalctl -u rabbitmq-server -f --no-pager'

# ── Cleanup ───────────────────────────────────────────────────

clean: ## Xóa container + images
	$(COMPOSE) down --rmi local 2>/dev/null || true

destroy: ## Xóa TẤT CẢ (container + images)
	$(COMPOSE) down -v --rmi local 2>/dev/null || true
	docker volume prune -f 2>/dev/null || true
	@echo "✓ Destroyed"

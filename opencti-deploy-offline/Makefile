# ══════════════════════════════════════════════════════════════
# Infrastructure Test — ES + Redis + MinIO + RabbitMQ + OpenCTI
# ══════════════════════════════════════════════════════════════
#
# Test full stack trong Rocky Linux 9 container với systemd.
# Elasticsearch chạy container riêng (đã có sẵn).
#
# Usage:
#   make pack-app            # Pack OpenCTI source + deps
#   make pack-infra          # Pack infrastructure files
#   make test                # Full: pack + build + deploy infra + app + status
#   make test-infra          # Infra only: build + deploy infra + status
#   make status              # Service status
#   make exec                # Shell vào container
#   make destroy             # Xóa tất cả containers
#   make destroy-pack    # Xóa build artifacts
# ══════════════════════════════════════════════════════════════

COMPOSE   := docker compose
CONTAINER := opencti-test

.PHONY: pack-app pack-infra test test-infra status exec destroy destroy-pack help
.DEFAULT_GOAL := help

help:
	@echo ""
	@echo "  OpenCTI Offline Deploy"
	@echo "  ====================================="
	@echo "  make pack-app            Pack app (opencti-app-package.tar.gz)"
	@echo "  make pack-infra          Pack infra (opencti-infra-package.tar.gz)"
	@echo "  make test                Full stack test"
	@echo "  make test-infra          Infra only test"
	@echo "  make status              Service status"
	@echo "  make exec                Shell into container"
	@echo "  make destroy             Remove all containers"
	@echo "  make destroy-pack        Remove build artifacts"
	@echo ""

# -- Pack (on build machine) ---

pack-app:
	bash scripts/pack_app.sh

pack-infra:
	bash scripts/pack_infra.sh

# -- Test (Docker) ---

test: pack-app pack-infra
	$(COMPOSE) build
	$(COMPOSE) up -d
	@sleep 5
	docker exec $(CONTAINER) bash /root/opencti-deploy/scripts/setup_infra.sh
	docker exec $(CONTAINER) bash /root/opencti-deploy/scripts/setup_app.sh
	@$(MAKE) --no-print-directory status

test-infra:
	$(COMPOSE) build
	$(COMPOSE) up -d
	@sleep 5
	docker exec $(CONTAINER) bash /root/opencti-deploy/scripts/setup_infra.sh
	@$(MAKE) --no-print-directory status

status:
	@docker exec $(CONTAINER) bash -c '\
		for svc in redis minio rabbitmq-server opencti-platform opencti-worker@1 opencti-worker@2 opencti-worker@3; do \
			S=$$(systemctl is-active $$svc 2>/dev/null || echo inactive); \
			[ "$$S" = "active" ] && printf "  OK  %-24s %s\n" "$$svc" "$$S" \
			                     || printf "  --  %-24s %s\n" "$$svc" "$$S"; \
		done \
	'

exec:
	docker exec -it $(CONTAINER) bash

down:
	$(COMPOSE) down -v --rmi local 2>/dev/null || true
	@echo "Stopped"

destroy:
	$(COMPOSE) down -v --rmi local 2>/dev/null || true
	docker volume prune -f 2>/dev/null || true
	@echo "Destroyed"

destroy-pack:
	@echo "Will delete: pack outputs + build dirs"
	@echo "  files/opencti-app-package.tar.gz"
	@echo "  files/opencti-infra-package.tar.gz"
	@echo "  files/opencti-source.tar.gz"
	@echo "  files/python-deps.tar.gz"
	@echo "  files/python312.tar.gz"
	@echo "  files/nodejs22.tar.gz"
	@echo "  opencti-graphql/build/"
	@echo "  opencti-front/builder/prod/build/"
	@read -p "Confirm? [y/N] " ans && [ "$$ans" = "y" ] || exit 1
	rm -f files/opencti-app-package.tar.gz files/opencti-infra-package.tar.gz files/opencti-source.tar.gz files/python-deps.tar.gz
	rm -f files/python312.tar.gz files/nodejs22.tar.gz
	rm -rf ../opencti-platform/opencti-graphql/build
	rm -rf ../opencti-platform/opencti-front/builder/prod/build
	@echo "Done"

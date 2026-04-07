###############################################################################
# v2-connectors Makefile
#
# make start        → Start all connectors
# make stop         → Stop all connectors
# make build        → Build custom connector images
# make start-custom → Start only custom connectors (v2-nvd, v2-botnet)
###############################################################################

COMPOSE = docker compose -f docker-compose-connector.yml
CUSTOM_SERVICES = connector-v2-nvd connector-v2-botnet connector-v2-maltrail

.PHONY: help start stop restart build start-custom stop-custom restart-custom \
        status logs clean prune

## ─── ALL CONNECTORS ──────────────────────

start: build ## Start all connectors (build custom first)
	$(COMPOSE) up -d

stop: ## Stop all connectors
	$(COMPOSE) down

restart: build ## Restart all connectors
	$(COMPOSE) down && $(COMPOSE) up -d

## ─── CUSTOM CONNECTORS ──────────────────

build: ## Build custom connector images (always rebuild)
	$(COMPOSE) build --no-cache $(CUSTOM_SERVICES)

start-custom: build ## Start only custom connectors
	$(COMPOSE) up -d $(CUSTOM_SERVICES)

stop-custom: ## Stop only custom connectors
	$(COMPOSE) stop $(CUSTOM_SERVICES)

restart-custom: build ## Restart only custom connectors
	$(COMPOSE) stop $(CUSTOM_SERVICES)
	$(COMPOSE) up -d $(CUSTOM_SERVICES)

## ─── MONITORING ──────────────────────────

status: ## Show connector status
	@$(COMPOSE) ps

logs: ## Follow logs of all connectors
	$(COMPOSE) logs -f

## ─── CLEANUP ─────────────────────────────

prune: ## Xóa tất cả unused images
	docker image prune -a -f

clean: ## Remove custom connector images
	docker rmi v2-connector/nvd-cve:latest v2-connector/botnet:latest v2-connector/maltrail:latest 2>/dev/null || true

## ─── HELP ────────────────────────────────

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-18s %s\n", $$1, $$2}'

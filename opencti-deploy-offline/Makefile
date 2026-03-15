# ══════════════════════════════════════════════════════════════
# Infrastructure Test — ES + Redis + MinIO + RabbitMQ + OpenCTI
# ══════════════════════════════════════════════════════════════

.PHONY: start stop exec destroy destroy-pack

start:
	docker compose up -d

stop:
	docker compose down

exec:
	docker exec -it opencti-test bash

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

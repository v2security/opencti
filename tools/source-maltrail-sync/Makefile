.PHONY: build clean-build

## Build binary to deploy/
build:
	go build -o deploy/v2-ioc-maltrail-sync .
	@echo "Built: deploy/v2-ioc-maltrail-sync"

## Remove build artifacts
clean-build:
	rm -f deploy/v2-ioc-maltrail-sync
	@echo "Cleaned build artifacts"

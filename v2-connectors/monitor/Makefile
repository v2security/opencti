.PHONY: build clean-build

## Build both binaries to deploy/
build:
	go build -o deploy/connector-status ./cmd/connector-status
	go build -o deploy/connector-stats ./cmd/connector-stats
	@echo "Built: deploy/connector-status, deploy/connector-stats"

## Remove build artifacts
clean-build:
	rm -f deploy/connector-status deploy/connector-stats
	@echo "Cleaned build artifacts"

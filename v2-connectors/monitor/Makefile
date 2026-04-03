.PHONY: build clean-build

## Build both binaries to deploy/
build:
	go build -o deploy/connector-status ./cmd/connector-status
	go build -o deploy/connector-summary ./cmd/connector-summary
	@echo "Built: deploy/connector-status, deploy/connector-summary"

## Remove build artifacts
clean-build:
	rm -f deploy/connector-status deploy/connector-summary
	@echo "Cleaned build artifacts"

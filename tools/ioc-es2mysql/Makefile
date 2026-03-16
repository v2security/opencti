.PHONY: install build build-blacklist build-hashlist clean-build

## Install dependencies
install:
	pip3 install -r requirements.txt

## Build both binaries
build: build-blacklist build-hashlist

## Remove build artifacts
clean-build:
	rm -rf build/ *.spec deploy/v2-ioc-blacklist-sync deploy/v2-ioc-hashlist-sync

## Build ids_blacklist sync binary
build-blacklist:
	pyinstaller --onefile --name v2-ioc-blacklist-sync \
		--distpath deploy \
		--hidden-import pycti \
		--hidden-import mysql.connector \
		--hidden-import geoip2.database \
		--hidden-import yaml \
		--hidden-import dotenv \
		--collect-submodules pycti \
		ids_blacklist_sync/main.py
	@echo "Built: deploy/v2-ioc-blacklist-sync"

## Build hashlist sync binary
build-hashlist:
	pyinstaller --onefile --name v2-ioc-hashlist-sync \
		--distpath deploy \
		--hidden-import pycti \
		--hidden-import mysql.connector \
		--hidden-import geoip2.database \
		--hidden-import yaml \
		--hidden-import dotenv \
		--collect-submodules pycti \
		hashlist_sync/main.py
	@echo "Built: deploy/v2-ioc-hashlist-sync"

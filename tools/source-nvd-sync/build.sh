#!/usr/bin/env bash
# Build NVD CVE Connector with PyInstaller
# Output: dist/nvd-cve-connector (single executable)
#
# Usage:
#   cd tools/source-nvd-sync
#   bash build.sh
#
# Requirements:
#   pip install pyinstaller

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Check pyinstaller
if ! command -v pyinstaller &>/dev/null; then
    echo "Installing pyinstaller..."
    pip install pyinstaller
fi

echo "Building nvd-cve-connector..."
pyinstaller \
    --noconfirm \
    --clean \
    --onefile \
    --name nvd-cve-connector \
    --distpath dist \
    --workpath build \
    --specpath . \
    --paths src \
    --hidden-import connector \
    --hidden-import config \
    --hidden-import utils \
    --hidden-import clients \
    --hidden-import clients.nvd \
    --hidden-import clients.epss \
    --hidden-import parsers \
    --hidden-import parsers.cpe \
    --hidden-import parsers.cve \
    --hidden-import parsers.cvss \
    --hidden-import stix_builders \
    --hidden-import stix_builders.vulnerability \
    --hidden-import stix_builders.software \
    --hidden-import stix_builders.relationship \
    --hidden-import pycti \
    --hidden-import stix2 \
    --hidden-import yaml \
    src/__main__.py

echo ""
echo "Build complete: dist/nvd-cve-connector"
ls -lh dist/nvd-cve-connector

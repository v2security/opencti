"""NVD CVE Connector entry point."""

import os
import sys

# Ensure src/ is on sys.path so bare imports (e.g. 'from connector import ...')
# work regardless of how this module is invoked.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from connector import NvdCveConnector

if __name__ == "__main__":
    NvdCveConnector().start()

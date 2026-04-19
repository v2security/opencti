"""LOLDrivers Connector entry point."""

import os
import sys

# Ensure src/ is on sys.path so bare imports work from any working directory.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from connector import LolDriversConnector

if __name__ == "__main__":
    LolDriversConnector().start()

"""Maltrail IOC Connector entry point."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from connector import MaltrailConnector

if __name__ == "__main__":
    MaltrailConnector().start()

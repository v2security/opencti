"""
Configuration for the Maltrail IOC Connector.

All values come from config.yml or environment variables via get_config_variable.
Precedence: environment variable > config.yml > code default.
"""

import uuid

from pycti import get_config_variable

# Deterministic namespace for maltrail indicators
STIX_NAMESPACE = uuid.UUID("c3d4e5f6-a7b8-9012-cdef-123456789abc")

# Trail category labels (maps to maltrail/trails/static/ sub-directories)
TRAIL_LABELS = ["malware", "malicious", "suspicious"]

# Score mapping per label
LABEL_SCORES = {
    "malware": 90,
    "malicious": 70,
    "suspicious": 50,
}


class ConnectorConfig:
    """Holds all connector configuration, loaded once at startup."""

    def __init__(self, config: dict):
        # --- OpenCTI ---
        self.opencti_url = get_config_variable(
            "OPENCTI_URL", ["opencti", "url"], config
        )
        self.opencti_token = get_config_variable(
            "OPENCTI_TOKEN", ["opencti", "token"], config
        )

        # --- Connector base ---
        self.connector_id = get_config_variable(
            "CONNECTOR_ID", ["connector", "id"], config
        )
        self.connector_name = get_config_variable(
            "CONNECTOR_NAME",
            ["connector", "name"],
            config,
            default="Maltrail IOC",
        )
        self.connector_scope = get_config_variable(
            "CONNECTOR_SCOPE",
            ["connector", "scope"],
            config,
            default="indicator",
        )
        self.connector_log_level = get_config_variable(
            "CONNECTOR_LOG_LEVEL",
            ["connector", "log_level"],
            config,
            default="info",
        )
        self.connector_duration_period = get_config_variable(
            "CONNECTOR_DURATION_PERIOD",
            ["connector", "duration_period"],
            config,
            default="P1D",
        )

        # --- Maltrail ---
        self.maltrail_repo_url = get_config_variable(
            "MALTRAIL_REPO_URL",
            ["maltrail", "repo_url"],
            config,
            default="https://github.com/stamparm/maltrail.git",
        )
        self.maltrail_data_dir = get_config_variable(
            "MALTRAIL_DATA_DIR",
            ["maltrail", "data_dir"],
            config,
            default="tools/.data",
        )
        self.maltrail_bundle_size = int(
            get_config_variable(
                "MALTRAIL_BUNDLE_SIZE",
                ["maltrail", "bundle_size"],
                config,
                default=500,
            )
        )
        self.maltrail_valid_days = int(
            get_config_variable(
                "MALTRAIL_VALID_DAYS",
                ["maltrail", "valid_days"],
                config,
                default=30,
            )
        )

"""
Configuration for the V2Secure Honeypot Connector.

All values come from config.yml or environment variables via get_config_variable.
Precedence: environment variable > config.yml > code default.
"""

import uuid

from pycti import get_config_variable

# Deterministic namespace for honeypot STIX objects
STIX_NAMESPACE = uuid.UUID("b2c3d4e5-f6a7-8901-bcde-f23456789abc")


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
            default="V2Secure Honeypot",
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
            default="PT30M",
        )
        self.relationship_delay = int(
            get_config_variable(
                "CONNECTOR_RELATIONSHIP_DELAY",
                ["connector", "relationship_delay"],
                config,
                default=300,
            )
        )

        # --- Honeypot ---
        self.honeypot_file_path = get_config_variable(
            "HONEYPOT_FILE_PATH",
            ["honeypot", "file_path"],
            config,
            default="/opt/connector/data/IP_Reputation.csv",
        )
        self.honeypot_bundle_size = int(
            get_config_variable(
                "HONEYPOT_BUNDLE_SIZE",
                ["honeypot", "bundle_size"],
                config,
                default=500,
            )
        )
        self.honeypot_valid_days = int(
            get_config_variable(
                "HONEYPOT_VALID_DAYS",
                ["honeypot", "valid_days"],
                config,
                default=90,
            )
        )

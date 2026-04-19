"""
Configuration for the LOLDrivers Connector.

All values come from config.yml or environment variables via get_config_variable.
Precedence: environment variable > config.yml > code default.
"""

import uuid

from pycti import get_config_variable

# Deterministic namespace for LOLDrivers STIX objects
STIX_NAMESPACE = uuid.UUID("a1b2c3d4-e5f6-7890-abcd-ef1234567890")

LOLDRIVERS_URL = "https://www.loldrivers.io"


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
            default="LOLDrivers",
        )
        self.connector_scope = get_config_variable(
            "CONNECTOR_SCOPE",
            ["connector", "scope"],
            config,
            default="loldrivers",
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
        self.relationship_delay = int(
            get_config_variable(
                "CONNECTOR_RELATIONSHIP_DELAY",
                ["connector", "relationship_delay"],
                config,
                default=300,
            )
        )

        # --- LOLDrivers API ---
        self.loldrivers_api_url = get_config_variable(
            "LOLDRIVERS_API_URL",
            ["loldrivers", "api_url"],
            config,
            default="https://www.loldrivers.io/api/drivers.json",
        )
        self.loldrivers_request_timeout = int(
            get_config_variable(
                "LOLDRIVERS_REQUEST_TIMEOUT",
                ["loldrivers", "request_timeout"],
                config,
                default=60,
            )
        )
        self.loldrivers_import_malicious = get_config_variable(
            "LOLDRIVERS_IMPORT_MALICIOUS",
            ["loldrivers", "import_malicious"],
            config,
            default=True,
        )
        self.loldrivers_import_vulnerable = get_config_variable(
            "LOLDRIVERS_IMPORT_VULNERABLE",
            ["loldrivers", "import_vulnerable"],
            config,
            default=True,
        )
        self.loldrivers_bundle_size = int(
            get_config_variable(
                "LOLDRIVERS_BUNDLE_SIZE",
                ["loldrivers", "bundle_size"],
                config,
                default=50,
            )
        )
        self.loldrivers_create_indicators = get_config_variable(
            "LOLDRIVERS_CREATE_INDICATORS",
            ["loldrivers", "create_indicators"],
            config,
            default=True,
        )
        self.loldrivers_create_observables = get_config_variable(
            "LOLDRIVERS_CREATE_OBSERVABLES",
            ["loldrivers", "create_observables"],
            config,
            default=True,
        )

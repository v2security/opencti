"""
Configuration for the NVD CVE Connector.

All values come from config.yml or environment variables via get_config_variable.
Precedence: environment variable > config.yml > code default.
"""

import uuid

from pycti import get_config_variable

# Namespace UUID for deterministic Vulnerability IDs
STIX_NAMESPACE = uuid.UUID("00abedb4-aa42-466c-9c01-fed23315a9b7")

NVD_DETAIL_URL = "https://nvd.nist.gov/vuln/detail"


class ConnectorConfig:
    """Holds all connector configuration, loaded once at startup."""

    def __init__(self, config: dict):
        # --- OpenCTI (secrets from .env) ---
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
            default="NVD CVE",
        )
        self.connector_scope = get_config_variable(
            "CONNECTOR_SCOPE",
            ["connector", "scope"],
            config,
            default="cve",
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
            default="PT6H",
        )

        # --- NVD API (api_key from .env) ---
        self.nvd_api_key = get_config_variable(
            "NVD_API_KEY",
            ["nvd", "api_key"],
            config,
        )
        self.nvd_base_url = get_config_variable(
            "NVD_BASE_URL",
            ["nvd", "base_url"],
            config,
            default="https://services.nvd.nist.gov/rest/json/cves/2.0",
        )
        self.nvd_request_timeout = int(
            get_config_variable(
                "NVD_REQUEST_TIMEOUT",
                ["nvd", "request_timeout"],
                config,
                default=30,
            )
        )
        self.nvd_max_date_range = int(
            get_config_variable(
                "NVD_MAX_DATE_RANGE",
                ["nvd", "max_date_range"],
                config,
                default=120,
            )
        )

        # --- Sync modes ---
        self.nvd_maintain_data = get_config_variable(
            "NVD_MAINTAIN_DATA",
            ["nvd", "maintain_data"],
            config,
            default=True,
        )
        self.nvd_pull_history = get_config_variable(
            "NVD_PULL_HISTORY",
            ["nvd", "pull_history"],
            config,
            default=False,
        )
        self.nvd_history_start_year = int(
            get_config_variable(
                "NVD_HISTORY_START_YEAR",
                ["nvd", "history_start_year"],
                config,
                default=2019,
            )
        )

        # --- EPSS enrichment ---
        # FIRST API rate limit: 1000 req/min (public, no auth)
        # Default delay 0.1s → max ~600 req/min (safe margin)
        self.epss_enabled = get_config_variable(
            "EPSS_ENABLED", ["epss", "enabled"], config, default=True
        )
        self.epss_api_url = get_config_variable(
            "EPSS_API_URL",
            ["epss", "api_url"],
            config,
            default="https://api.first.org/data/v1/epss",
        )
        self.epss_request_timeout = int(
            get_config_variable(
                "EPSS_REQUEST_TIMEOUT",
                ["epss", "request_timeout"],
                config,
                default=30,
            )
        )
        self.epss_request_delay = float(
            get_config_variable(
                "EPSS_REQUEST_DELAY",
                ["epss", "request_delay"],
                config,
                default=0.1,
            )
        )
        self.epss_batch_size = min(
            int(
                get_config_variable(
                    "EPSS_BATCH_SIZE",
                    ["epss", "batch_size"],
                    config,
                    default=30,
                )
            ),
            100,
        )

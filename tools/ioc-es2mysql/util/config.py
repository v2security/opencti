"""util.config — load ``config.yaml``, resolve ``${VAR}`` placeholders from ``.env``.

Environment variables referenced as ``${VAR_NAME}`` in the YAML file are
expanded at load time.  If a referenced variable is not set in ``.env`` or
the process environment the program exits immediately with a clear message.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

import yaml
from dotenv import load_dotenv

_PROJECT_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(_PROJECT_ROOT / ".env")

_ENV_RE = re.compile(r"\$\{([^}]+)\}")


def _resolve(node):
    """Recursively replace ``${VAR}`` placeholders with environment values."""
    if isinstance(node, str):
        def _repl(m: re.Match) -> str:
            var = m.group(1)
            val = os.environ.get(var)
            if val is None:
                sys.exit(f"[config] ${{{var}}} not set in .env or environment.")
            return val
        return _ENV_RE.sub(_repl, node)
    if isinstance(node, dict):
        return {k: _resolve(v) for k, v in node.items()}
    if isinstance(node, list):
        return [_resolve(i) for i in node]
    return node


def load_config() -> dict:
    """Read ``config.yaml``, resolve ``${VAR}`` references, and validate required fields.

    Exits the process if the file is missing or a required field is empty.
    """
    path = _PROJECT_ROOT / "config.yaml"
    if not path.exists():
        sys.exit(f"[config] config.yaml not found at {path}")
    with open(path, "r", encoding="utf-8") as f:
        raw = yaml.safe_load(f) or {}
    cfg = _resolve(raw)

    # Validate required fields.
    for key in ("opencti.api_url", "opencti.api_token", "mysql.password"):
        parts = key.split(".")
        v = cfg
        for p in parts:
            v = v.get(p) if isinstance(v, dict) else None
        if not v:
            sys.exit(f"[config] Missing required field: {key}")

    return cfg

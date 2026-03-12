"""
Patched check_indicator.py — EQL subprocess isolation fix.

Original:
opencti-platform/opencti-graphql/src/python/runtime/check_indicator.py

Problem:
`import eql` at module level causes SEGV (signal 11) when loaded
through node-calls-python's embedded Python interpreter.

Fix:
Run eql validation in a subprocess instead of in-process import.

Tested:
Rocky Linux 9
Python 3.12.8
Node.js v22.15.0
eql 0.9.19
"""

import subprocess
import sys

import yara
from parsuricata import parse_rules
from sigma.parser.collection import SigmaCollectionParser
from snort.snort_parser import Parser
from stix2patterns.validator import run_validator

from utils.runtime_utils import return_data


def check_indicator(pattern_type, indicator_value):
    """Validate indicator pattern by type"""

    # STIX
    if pattern_type == "stix":
        result = False
        try:
            errors = run_validator(indicator_value)
            if len(errors) == 0:
                result = True
        except Exception:
            result = False

        return {"status": "success", "data": result}

    # YARA
    if pattern_type == "yara":
        try:
            yara.compile(source=indicator_value)
            result = True
        except Exception:
            result = False

        return {"status": "success", "data": result}

    # SIGMA
    if pattern_type == "sigma":
        try:
            SigmaCollectionParser(indicator_value)
            result = True
        except Exception:
            result = False

        return {"status": "success", "data": result}

    # SNORT
    if pattern_type == "snort":
        try:
            Parser(indicator_value)
            result = True
        except Exception:
            result = False

        return {"status": "success", "data": result}

    # SURICATA
    if pattern_type == "suricata":
        try:
            parse_rules(indicator_value)
            result = True
        except Exception:
            result = False

        return {"status": "success", "data": result}

    # EQL
    if pattern_type == "eql":
        try:
            eql_script = (
                "import eql\n"
                "with eql.parser.elasticsearch_syntax, "
                "eql.parser.ignore_missing_functions:\n"
                "    eql.parse_query(r'''"
                + indicator_value
                + "''')\n"
                "print('OK')"
            )

            proc = subprocess.run(
                [sys.executable, "-c", eql_script],
                capture_output=True,
                text=True,
                timeout=10,
            )

            result = proc.returncode == 0 and "OK" in proc.stdout

        except Exception:
            result = False

        return {"status": "success", "data": result}

    return {"status": "unknown", "data": None}


if __name__ == "__main__":

    if len(sys.argv) <= 2:
        return_data(
            {"status": "error", "message": "Missing argument to the Python script"}
        )

    if sys.argv[1] == "check":
        return_data({"status": "success"})

    data = check_indicator(sys.argv[1], sys.argv[2])
    return_data(data)
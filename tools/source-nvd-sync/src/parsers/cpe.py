"""CPE 2.3 parsing and extraction from CVE configurations."""


def parse_cpe(cpe_string: str) -> dict[str, str]:
    """Parse a CPE 2.3 string into its component fields.

    Returns empty dict if the string is malformed.
    Fields with wildcard (*) or NA (-) values are returned as empty strings.
    """
    parts = cpe_string.split(":")
    if len(parts) < 5:
        return {}

    def _val(index: int) -> str:
        return parts[index] if len(parts) > index and parts[index] not in ("*", "-") else ""

    return {
        "cpe": cpe_string,
        "part": _val(2),
        "vendor": _val(3),
        "product": _val(4),
        "version": _val(5),
        "update": _val(6),
        "edition": _val(7),
        "language": _val(8),
        "sw_edition": _val(9),
        "target_sw": _val(10),
        "target_hw": _val(11),
    }


def extract_vulnerable_cpes(cve_data: dict) -> list[dict]:
    """Extract all vulnerable CPE match entries from CVE configurations.

    Returns a list of dicts with 'criteria' (CPE string) and optional
    version range fields (versionStartIncluding, versionEndExcluding, etc.).
    """
    results: list[dict] = []
    seen_cpes: set[str] = set()

    for config in cve_data.get("configurations", []):
        for node in config.get("nodes", []):
            for match in node.get("cpeMatch", []):
                if not match.get("vulnerable", False):
                    continue
                cpe_str = match.get("criteria", "")
                if cpe_str and cpe_str not in seen_cpes:
                    seen_cpes.add(cpe_str)
                    results.append(match)
    return results

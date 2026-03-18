"""CVE data extraction helpers."""


def get_description(cve_data: dict) -> str:
    """Extract the English description from a CVE entry."""
    for desc in cve_data.get("descriptions", []):
        if desc.get("lang") == "en":
            return desc["value"]
    return ""


def extract_cwe_ids(cve_data: dict) -> list[str]:
    """Extract unique CWE IDs from CVE weaknesses, excluding NVD-CWE-* placeholders."""
    cwe_ids: list[str] = []
    seen: set[str] = set()
    for weakness in cve_data.get("weaknesses", []):
        for desc in weakness.get("description", []):
            value = desc.get("value", "")
            if value.startswith("CWE-") and value not in seen:
                seen.add(value)
                cwe_ids.append(value)
    return cwe_ids

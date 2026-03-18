"""CVSS metric extraction and mapping to OpenCTI properties."""

from typing import Any


def _pick_best_metric(entries: list[dict]) -> dict | None:
    """Pick the metric entry with the highest baseScore. Prefer 'Primary' type on ties."""
    if not entries:
        return None
    return max(
        entries,
        key=lambda e: (
            e.get("cvssData", {}).get("baseScore", 0),
            e.get("type") == "Primary",
        ),
    )


def get_cvss_v31(cve_data: dict) -> dict | None:
    """Extract the best CVSS v3.1 cvssData dict from a CVE entry."""
    entries = cve_data.get("metrics", {}).get("cvssMetricV31", [])
    best = _pick_best_metric(entries)
    return best.get("cvssData") if best else None


def get_cvss_v2(cve_data: dict) -> dict | None:
    """Extract the best CVSS v2 cvssData dict from a CVE entry."""
    entries = cve_data.get("metrics", {}).get("cvssMetricV2", [])
    best = _pick_best_metric(entries)
    return best.get("cvssData") if best else None


def get_cvss_v4(cve_data: dict) -> dict | None:
    """Extract the best CVSS v4.0 cvssData dict from a CVE entry."""
    entries = cve_data.get("metrics", {}).get("cvssMetricV40", [])
    best = _pick_best_metric(entries)
    return best.get("cvssData") if best else None


def cvss_to_opencti_score(cvss_score: float) -> int:
    """Convert CVSS 0-10 scale to OpenCTI 0-100 score."""
    return min(100, max(0, round(cvss_score * 10)))


# ---------------------------------------------------------------------------
# OpenCTI CVSS property builders
# ---------------------------------------------------------------------------

def build_cvss_v31_props(cvss_data: dict) -> dict[str, Any]:
    """Map NVD CVSS v3.1 data to OpenCTI x_opencti_cvss_* properties."""
    mapping = {
        "vectorString": "x_opencti_cvss_vector_string",
        "baseScore": "x_opencti_cvss_base_score",
        "baseSeverity": "x_opencti_cvss_base_severity",
        "attackVector": "x_opencti_cvss_attack_vector",
        "attackComplexity": "x_opencti_cvss_attack_complexity",
        "privilegesRequired": "x_opencti_cvss_privileges_required",
        "userInteraction": "x_opencti_cvss_user_interaction",
        "scope": "x_opencti_cvss_scope",
        "confidentialityImpact": "x_opencti_cvss_confidentiality_impact",
        "integrityImpact": "x_opencti_cvss_integrity_impact",
        "availabilityImpact": "x_opencti_cvss_availability_impact",
    }
    return {octi_key: cvss_data[nvd_key] for nvd_key, octi_key in mapping.items() if nvd_key in cvss_data}


def build_cvss_v2_props(cvss_data: dict) -> dict[str, Any]:
    """Map NVD CVSS v2 data to OpenCTI x_opencti_cvss_v2_* properties."""
    mapping = {
        "vectorString": "x_opencti_cvss_v2_vector_string",
        "baseScore": "x_opencti_cvss_v2_base_score",
        "accessVector": "x_opencti_cvss_v2_access_vector",
        "accessComplexity": "x_opencti_cvss_v2_access_complexity",
        "authentication": "x_opencti_cvss_v2_authentication",
        "confidentialityImpact": "x_opencti_cvss_v2_confidentiality_impact",
        "integrityImpact": "x_opencti_cvss_v2_integrity_impact",
        "availabilityImpact": "x_opencti_cvss_v2_availability_impact",
    }
    return {octi_key: cvss_data[nvd_key] for nvd_key, octi_key in mapping.items() if nvd_key in cvss_data}


def build_cvss_v4_props(cvss_data: dict) -> dict[str, Any]:
    """Map NVD CVSS v4.0 data to OpenCTI x_opencti_cvss_v4_* properties."""
    mapping = {
        "vectorString": "x_opencti_cvss_v4_vector_string",
        "baseScore": "x_opencti_cvss_v4_base_score",
        "baseSeverity": "x_opencti_cvss_v4_base_severity",
        "attackVector": "x_opencti_cvss_v4_attack_vector",
        "attackComplexity": "x_opencti_cvss_v4_attack_complexity",
        "attackRequirements": "x_opencti_cvss_v4_attack_requirements",
        "privilegesRequired": "x_opencti_cvss_v4_privileges_required",
        "userInteraction": "x_opencti_cvss_v4_user_interaction",
        "vulnConfidentialityImpact": "x_opencti_cvss_v4_confidentiality_impact_v",
        "subConfidentialityImpact": "x_opencti_cvss_v4_confidentiality_impact_s",
        "vulnIntegrityImpact": "x_opencti_cvss_v4_integrity_impact_v",
        "subIntegrityImpact": "x_opencti_cvss_v4_integrity_impact_s",
        "vulnAvailabilityImpact": "x_opencti_cvss_v4_availability_impact_v",
        "subAvailabilityImpact": "x_opencti_cvss_v4_availability_impact_s",
        "exploitMaturity": "x_opencti_cvss_v4_exploit_maturity",
    }
    props = {octi_key: cvss_data[nvd_key] for nvd_key, octi_key in mapping.items() if nvd_key in cvss_data}

    # Sanitize vector string: OpenCTI only accepts base + E metrics
    if "x_opencti_cvss_v4_vector_string" in props:
        props["x_opencti_cvss_v4_vector_string"] = _sanitize_cvss4_vector(
            props["x_opencti_cvss_v4_vector_string"]
        )

    return props


# Metrics accepted by OpenCTI's CVSS4 validator
_CVSS4_ALLOWED_METRICS = {"AV", "AC", "AT", "PR", "UI", "VC", "VI", "VA", "SC", "SI", "SA", "E"}


def _sanitize_cvss4_vector(vector: str) -> str:
    """Strip supplemental/environmental metrics that OpenCTI doesn't accept."""
    if not vector.startswith("CVSS:4.0/"):
        return vector
    body = vector[len("CVSS:4.0/"):]
    filtered = [
        segment for segment in body.split("/")
        if segment.split(":")[0] in _CVSS4_ALLOWED_METRICS
    ]
    return "CVSS:4.0/" + "/".join(filtered)

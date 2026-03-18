"""Shared utility functions."""


def camel_to_snake(name: str) -> str:
    """Convert camelCase to snake_case."""
    result: list[str] = []
    for i, ch in enumerate(name):
        if ch.isupper() and i > 0:
            result.append("_")
        result.append(ch.lower())
    return "".join(result)


def normalize_timestamp(ts: str) -> str | None:
    """Ensure NVD timestamps end with 'Z' for STIX2 compliance."""
    if not ts:
        return None
    return ts + "Z" if not ts.endswith("Z") else ts
